local lookup = require("glossa.lookup")
local review = require("glossa.review")
local store = require("glossa.store")
local window = require("glossa.window")

local M = {}

local defaults = {
  provider = "google",
  data_file = vim.fn.stdpath("data") .. "/glossa.nvim/cards.json",
  lookup = {
    source_lang = "auto",
    target_lang = "ko",
  },
  replace = {
    source_lang = "auto",
    target_lang = "ko",
  },
  google = {
    endpoint = "https://translate.googleapis.com/translate_a/single",
    timeout_ms = 8000,
  },
  window = {
    border = "rounded",
    max_width = 0.55,
    max_height = 0.6,
  },
}

local state = {
  opts = vim.deepcopy(defaults),
  last_entry = nil,
  lookup_window = nil,
  pending_lookup = nil,
  request_id = 0,
  registered = false,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "glossa.nvim" })
end

local function normalize_text(text)
  if type(text) ~= "string" then
    return nil
  end

  local normalized = vim.trim(text)
  if normalized == "" then
    return nil
  end

  return normalized
end

local function get_range_text(line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  return normalize_text(table.concat(lines, "\n"))
end

local function is_before(pos1, pos2)
  return pos1[2] < pos2[2] or (pos1[2] == pos2[2] and pos1[3] <= pos2[3])
end

local function get_visual_selection()
  local mode = vim.fn.mode()
  local start_pos
  local end_pos
  local visual_type

  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
    visual_type = mode
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
    visual_type = vim.fn.visualmode()
  end

  if visual_type == "" then
    visual_type = "v"
  end

  if not is_before(start_pos, end_pos) then
    start_pos, end_pos = end_pos, start_pos
  end

  local lines = vim.fn.getregion(start_pos, end_pos, { type = visual_type })

  return {
    start_pos = start_pos,
    end_pos = end_pos,
    visual_type = visual_type,
    text = normalize_text(table.concat(lines, "\n")),
  }
end

local function get_visual_text()
  local selection = get_visual_selection()
  if not selection then
    return nil
  end

  return selection.text
end

local function build_request_opts(operation)
  local opts = vim.deepcopy(state.opts)
  local config = opts[operation] or {}

  opts.source_lang = config.source_lang
  opts.target_lang = config.target_lang

  return opts
end

local function make_visual_target(selection)
  if not selection or not selection.text then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()

  if selection.visual_type == "V" then
    return {
      bufnr = bufnr,
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      mode = "line",
      start_row = selection.start_pos[2] - 1,
      end_row = selection.end_pos[2],
    }
  end

  if selection.visual_type == "\22" then
    return {
      bufnr = bufnr,
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      mode = "block",
    }
  end

  return {
    bufnr = bufnr,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    mode = "char",
    start_row = selection.start_pos[2] - 1,
    start_col = selection.start_pos[3] - 1,
    end_row = selection.end_pos[2] - 1,
    end_col = selection.end_pos[3],
  }
end

local function capture_range_target(line1, line2)
  local first = math.min(line1, line2)
  local last = math.max(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf()

  return {
    bufnr = bufnr,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    mode = "line",
    start_row = first - 1,
    end_row = last,
  }
end

local function capture_word_target()
  local word = normalize_text(vim.fn.expand("<cword>"))
  if not word then
    return nil, nil
  end

  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  local col = vim.fn.col(".")
  local line = vim.api.nvim_get_current_line()
  local from = 1

  while true do
    local start_col, end_col = line:find(word, from, true)
    if not start_col then
      break
    end

    if start_col <= col and col <= end_col then
      local bufnr = vim.api.nvim_get_current_buf()

      return {
        bufnr = bufnr,
        changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
        mode = "char",
        start_row = row - 1,
        start_col = start_col - 1,
        end_row = row - 1,
        end_col = end_col,
      }, word
    end

    from = start_col + 1
  end

  return nil, word
end

local function apply_replacement(target, replacement)
  if not target then
    notify("Nothing to replace.", vim.log.levels.WARN)
    return false
  end

  if target.mode == "block" then
    notify("Blockwise visual replace is not supported yet.", vim.log.levels.WARN)
    return false
  end

  if type(replacement) ~= "string" or replacement == "" then
    notify("No translation returned for replacement.", vim.log.levels.WARN)
    return false
  end

  if not vim.api.nvim_buf_is_valid(target.bufnr) then
    notify("Target buffer is no longer valid.", vim.log.levels.WARN)
    return false
  end

  local changedtick = vim.api.nvim_buf_get_changedtick(target.bufnr)
  if changedtick ~= target.changedtick then
    notify("Buffer changed before replacement completed.", vim.log.levels.WARN)
    return false
  end

  local replacement_lines = vim.split(replacement, "\n", { plain = true })

  if target.mode == "line" then
    vim.api.nvim_buf_set_lines(target.bufnr, target.start_row, target.end_row, false, replacement_lines)
    return true
  end

  vim.api.nvim_buf_set_text(
    target.bufnr,
    target.start_row,
    target.start_col,
    target.end_row,
    target.end_col,
    replacement_lines
  )

  return true
end

local function resolve_query(command_opts)
  if command_opts.args ~= "" then
    return normalize_text(command_opts.args)
  end

  if command_opts.range > 0 then
    return get_range_text(command_opts.line1, command_opts.line2)
  end

  return normalize_text(vim.fn.expand("<cword>"))
end

local function close_lookup_window()
  if state.lookup_window then
    window.close(state.lookup_window)
    state.lookup_window = nil
  end
end

local function on_lookup_window_close(win, cancel_pending)
  if state.lookup_window == win then
    state.lookup_window = nil
  end

  if not cancel_pending then
    return
  end

  local pending = state.pending_lookup
  if not pending then
    return
  end

  state.pending_lookup = nil

  if pending.handle and pending.handle.kill then
    pcall(function()
      pending.handle:kill(15)
    end)
  end
end

local function clear_pending_lookup(cancel_process)
  local pending = state.pending_lookup
  if not pending then
    return
  end

  state.pending_lookup = nil

  if cancel_process and pending.handle and pending.handle.kill then
    pcall(function()
      pending.handle:kill(15)
    end)
  end

  close_lookup_window()
end

local function open_loading(action, query)
  close_lookup_window()

  state.lookup_window = window.open({
    title = " Glossa ",
    footer = " q cancel ",
    enter = true,
    wrap = true,
    notify_in_headless = false,
    on_close = function(win)
      on_lookup_window_close(win, true)
    end,
    lines = {
      "  " .. action,
      "",
      "  " .. query,
    },
    highlights = {
      { group = "GlossaSection", line = 0, col_start = 2, col_end = -1 },
      { group = "GlossaTerm", line = 2, col_start = 2, col_end = -1 },
    },
    opts = state.opts.window,
  })
end

local function start_request(query, request_opts, action, on_success)
  clear_pending_lookup(true)

  state.request_id = state.request_id + 1
  local request_id = state.request_id
  open_loading(action, query)
  state.pending_lookup = {
    id = request_id,
  }

  local ok, handle = pcall(lookup.lookup_async, query, request_opts, function(err, entry)
    if not state.pending_lookup or state.pending_lookup.id ~= request_id then
      return
    end

    state.pending_lookup = nil

    if err then
      close_lookup_window()
      notify(err, vim.log.levels.ERROR)
      return
    end

    state.last_entry = entry
    on_success(entry)
  end)

  if not ok then
    state.pending_lookup = nil
    close_lookup_window()
    notify(handle, vim.log.levels.ERROR)
    return nil
  end

  state.pending_lookup.handle = handle
  return handle
end

local function render_entry(entry)
  local view = lookup.render_lines(entry)

  close_lookup_window()

  state.lookup_window = window.open({
    title = " Glossa ",
    footer = " q close ",
    lines = view.lines,
    highlights = view.highlights,
    wrap = true,
    enter = true,
    on_close = function(win)
      on_lookup_window_close(win, false)
    end,
    opts = state.opts.window,
  })
end

local function ensure_last_entry()
  if state.last_entry then
    return state.last_entry
  end

  notify("No lookup result yet. Run :GlossaLookup first.", vim.log.levels.WARN)
  return nil
end

function M.setup(opts)
  state.opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.lookup_text(text)
  local query = normalize_text(text)
  if not query then
    notify("Nothing to look up.", vim.log.levels.WARN)
    return nil
  end

  return start_request(query, build_request_opts("lookup"), "Looking up", render_entry)
end

function M.lookup_command(command_opts)
  return M.lookup_text(resolve_query(command_opts))
end

function M.lookup_visual()
  return M.lookup_text(get_visual_text())
end

function M.replace_text(text, target)
  local query = normalize_text(text)
  if not query then
    notify("Nothing to replace.", vim.log.levels.WARN)
    return nil
  end

  return start_request(query, build_request_opts("replace"), "Replacing", function(entry)
    close_lookup_window()
    apply_replacement(target, entry.translation)
  end)
end

function M.replace_current_word()
  local target, word = capture_word_target()
  return M.replace_text(word, target)
end

function M.replace_command(command_opts)
  local query = resolve_query(command_opts)
  local target = command_opts.range > 0 and capture_range_target(command_opts.line1, command_opts.line2)
    or select(1, capture_word_target())

  return M.replace_text(query, target)
end

function M.replace_visual()
  local selection = get_visual_selection()
  return M.replace_text(selection and selection.text, make_visual_target(selection))
end

function M.save_last()
  local entry = ensure_last_entry()
  if not entry then
    return
  end

  local result = store.save_entry(state.opts.data_file, entry)
  notify(("Saved '%s' (%d cards total)"):format(entry.term, result.count))
end

function M.review_due()
  local entries = store.list_due(state.opts.data_file)

  window.open({
    title = " Review ",
    footer = " q close ",
    lines = review.render_lines(entries),
    opts = state.opts.window,
  })
end

function M.show_stats()
  local stats = store.stats(state.opts.data_file)
  notify(
    ("cards=%d due=%d provider=%s"):format(stats.total, stats.due, state.opts.provider)
  )
end

function M.register()
  if state.registered then
    return
  end

  state.registered = true

  vim.api.nvim_create_user_command("GlossaLookup", function(opts)
    M.lookup_command(opts)
  end, {
    desc = "Look up the current word, range, or explicit text",
    nargs = "*",
    range = true,
  })

  vim.api.nvim_create_user_command("GlossaSave", function()
    M.save_last()
  end, {
    desc = "Save the last lookup result as a study card",
  })

  vim.api.nvim_create_user_command("GlossaReplace", function(opts)
    M.replace_command(opts)
  end, {
    desc = "Replace the current word, range, or selection with a translation",
    nargs = "*",
    range = true,
  })

  vim.api.nvim_create_user_command("GlossaReview", function()
    M.review_due()
  end, {
    desc = "Show saved cards that are due for review",
  })

  vim.api.nvim_create_user_command("GlossaStats", function()
    M.show_stats()
  end, {
    desc = "Show study card statistics",
  })

  vim.keymap.set("n", "<Plug>(GlossaLookup)", function()
    M.lookup_text(vim.fn.expand("<cword>"))
  end, {
    desc = "Look up the word under the cursor",
    silent = true,
  })

  vim.keymap.set("x", "<Plug>(GlossaLookup)", function()
    M.lookup_visual()
  end, {
    desc = "Look up the current visual selection",
    silent = true,
  })

  vim.keymap.set("n", "<Plug>(GlossaReplace)", function()
    M.replace_current_word()
  end, {
    desc = "Replace the word under the cursor with a translation",
    silent = true,
  })

  vim.keymap.set("x", "<Plug>(GlossaReplace)", function()
    M.replace_visual()
  end, {
    desc = "Replace the current visual selection with a translation",
    silent = true,
  })

  vim.keymap.set("n", "<Plug>(GlossaSave)", function()
    M.save_last()
  end, {
    desc = "Save the last lookup result",
    silent = true,
  })

  vim.keymap.set("n", "<Plug>(GlossaReview)", function()
    M.review_due()
  end, {
    desc = "Open the due review list",
    silent = true,
  })

  vim.keymap.set("n", "<Plug>(GlossaStats)", function()
    M.show_stats()
  end, {
    desc = "Show study statistics",
    silent = true,
  })
end

return M
