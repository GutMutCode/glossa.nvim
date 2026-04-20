local lookup = require("glossa.lookup")
local review = require("glossa.review")
local store = require("glossa.store")
local window = require("glossa.window")

local M = {}

local defaults = {
  provider = "google",
  source_lang = "auto",
  target_lang = "ko",
  data_file = vim.fn.stdpath("data") .. "/glossa.nvim/cards.json",
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

local function get_visual_text()
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

  local lines = vim.fn.getregion(start_pos, end_pos, { type = visual_type })

  return normalize_text(table.concat(lines, "\n"))
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

local function open_loading(query)
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
      "  Looking up",
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

  clear_pending_lookup(true)

  state.request_id = state.request_id + 1
  local request_id = state.request_id
  open_loading(query)
  state.pending_lookup = {
    id = request_id,
  }

  local ok, handle = pcall(lookup.lookup_async, query, state.opts, function(err, entry)
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
    render_entry(entry)
  end)

  if not ok then
    state.pending_lookup = nil
    close_lookup_window()
    notify(handle, vim.log.levels.ERROR)
    return nil
  end

  state.pending_lookup.handle = handle
  return nil
end

function M.lookup_command(command_opts)
  return M.lookup_text(resolve_query(command_opts))
end

function M.lookup_visual()
  return M.lookup_text(get_visual_text())
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
