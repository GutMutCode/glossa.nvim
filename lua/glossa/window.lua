local M = {}

local highlights_ready = false

local function ensure_highlights()
  if highlights_ready then
    return
  end

  highlights_ready = true

  vim.api.nvim_set_hl(0, "GlossaNormalFloat", { default = true, link = "NormalFloat" })
  vim.api.nvim_set_hl(0, "GlossaFloatBorder", { default = true, link = "FloatBorder" })
  vim.api.nvim_set_hl(0, "GlossaFloatTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "GlossaFloatFooter", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "GlossaSection", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "GlossaTerm", { default = true, link = "Identifier" })
  vim.api.nvim_set_hl(0, "GlossaMeta", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "GlossaTranslation", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "GlossaValue", { default = true, link = "Normal" })
  vim.api.nvim_set_hl(0, "GlossaAlt", { default = true, link = "Constant" })
  vim.api.nvim_set_hl(0, "GlossaBullet", { default = true, link = "Delimiter" })
  vim.api.nvim_set_hl(0, "GlossaMuted", { default = true, link = "Comment" })
end

local function apply_highlights(buf, highlights)
  for _, item in ipairs(highlights or {}) do
    vim.api.nvim_buf_add_highlight(
      buf,
      -1,
      item.group,
      item.line,
      item.col_start,
      item.col_end
    )
  end
end

local function resolve_dimension(value, total, fallback)
  if type(value) ~= "number" then
    return fallback
  end

  if value > 0 and value < 1 then
    return math.max(1, math.floor(total * value))
  end

  return math.max(1, math.floor(value))
end

local function measure_width(lines)
  local width = 1

  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  return width
end

function M.open(spec)
  local lines = vim.deepcopy(spec.lines or {})
  local highlights = vim.deepcopy(spec.highlights or {})
  local opts = spec.opts or {}

  if #lines == 0 then
    lines = { "(empty)" }
  end

  if #vim.api.nvim_list_uis() == 0 then
    if spec.notify_in_headless == false then
      return nil
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, {
      title = spec.title or "glossa.nvim",
    })
    return nil
  end

  ensure_highlights()

  local max_width = resolve_dimension(opts.max_width, vim.o.columns, math.floor(vim.o.columns * 0.55))
  local max_height = resolve_dimension(opts.max_height, vim.o.lines - 2, math.floor(vim.o.lines * 0.6))
  local width = math.min(max_width, measure_width(lines) + 2)
  local height = math.min(max_height, #lines)
  local buf = vim.api.nvim_create_buf(false, true)
  local enter = spec.enter == nil and true or spec.enter
  local win = vim.api.nvim_open_win(buf, enter, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    title = spec.title,
    title_pos = "center",
    footer = spec.footer,
    footer_pos = "right",
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  apply_highlights(buf, highlights)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "glossa"
  vim.bo[buf].modifiable = false
  vim.bo[buf].swapfile = false
  vim.wo[win].wrap = spec.wrap == true
  vim.wo[win].linebreak = spec.wrap == true
  vim.wo[win].winhighlight = table.concat({
    "NormalFloat:GlossaNormalFloat",
    "FloatBorder:GlossaFloatBorder",
    "FloatTitle:GlossaFloatTitle",
    "FloatFooter:GlossaFloatFooter",
  }, ",")

  vim.keymap.set("n", "q", function()
    if spec.on_close then
      pcall(spec.on_close, win)
    end

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, {
    buffer = buf,
    nowait = true,
    silent = true,
  })

  return win
end

function M.close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

return M
