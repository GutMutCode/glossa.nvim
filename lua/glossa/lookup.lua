local M = {}

local function normalize_entry(entry, text, opts)
  if type(entry) ~= "table" then
    error(("glossa.nvim provider '%s' returned an invalid result"):format(opts.provider), 0)
  end

  entry.term = entry.term or vim.trim(text)
  entry.source_text = entry.source_text or text
  entry.source_lang = entry.source_lang or opts.source_lang
  entry.target_lang = entry.target_lang or opts.target_lang
  entry.examples = entry.examples or {}
  entry.notes = entry.notes or {}

  return entry
end

local function push_line(view, text, spans)
  local line = #view.lines
  table.insert(view.lines, text)

  for _, span in ipairs(spans or {}) do
    table.insert(view.highlights, {
      group = span.group,
      line = line,
      col_start = span.col_start,
      col_end = span.col_end,
    })
  end
end

local function push_blank(view)
  push_line(view, "")
end

local function push_section(view, title, value, line_group)
  if value == nil then
    return
  end

  if type(value) == "string" then
    if value == "" then
      return
    end

    if #view.lines > 0 then
      push_blank(view)
    end

    push_line(view, "  " .. title, {
      { group = "GlossaSection", col_start = 2, col_end = 2 + #title },
    })
    push_line(view, "    " .. value, {
      { group = line_group or "GlossaValue", col_start = 4, col_end = -1 },
    })
    return
  end

  if vim.islist(value) and #value > 0 then
    if #view.lines > 0 then
      push_blank(view)
    end

    push_line(view, "  " .. title, {
      { group = "GlossaSection", col_start = 2, col_end = 2 + #title },
    })

    for _, item in ipairs(value) do
      local text = "    - " .. item
      push_line(view, text, {
        { group = "GlossaBullet", col_start = 4, col_end = 5 },
        { group = line_group or "GlossaValue", col_start = 6, col_end = -1 },
      })
    end
  end
end

local function load_provider(name)
  local ok, provider = pcall(require, "glossa.providers." .. name)
  if ok then
    return provider
  end

  error(("glossa.nvim could not load provider '%s'"):format(name))
end

function M.lookup(text, opts)
  local provider = load_provider(opts.provider)
  local ok, entry = pcall(provider.lookup, text, opts)
  if not ok then
    error(entry, 0)
  end

  return normalize_entry(entry, text, opts)
end

function M.lookup_async(text, opts, callback)
  local provider = load_provider(opts.provider)

  local function finish(err, entry)
    if err then
      callback(err)
      return
    end

    local ok, normalized = pcall(normalize_entry, entry, text, opts)
    if not ok then
      callback(normalized)
      return
    end

    callback(nil, normalized)
  end

  if type(provider.lookup_async) == "function" then
    local ok, handle = pcall(provider.lookup_async, text, opts, finish)
    if not ok then
      vim.schedule(function()
        callback(handle)
      end)
      return nil
    end

    return handle
  end

  vim.schedule(function()
    local ok, entry = pcall(provider.lookup, text, opts)
    if not ok then
      callback(entry)
      return
    end

    finish(nil, entry)
  end)

  return nil
end

function M.render_lines(entry)
  local view = {
    lines = {},
    highlights = {},
  }
  local meta = {
    ("%s -> %s"):format(entry.source_lang, entry.target_lang),
  }

  if entry.kind then
    table.insert(meta, entry.kind)
  end

  if entry.phonetic and entry.phonetic ~= "" then
    table.insert(meta, "/" .. entry.phonetic .. "/")
  end

  push_line(view, "  " .. entry.term, {
    { group = "GlossaTerm", col_start = 2, col_end = -1 },
  })
  push_line(view, "  " .. table.concat(meta, "   "), {
    { group = "GlossaMeta", col_start = 2, col_end = -1 },
  })

  push_section(view, "Translation", entry.translation, "GlossaTranslation")
  push_section(view, "Explanation", entry.explanation)
  push_section(view, "Examples", entry.examples)
  push_section(view, "Alternatives", entry.alternatives, "GlossaAlt")
  push_section(view, "Notes", entry.notes, "GlossaMuted")

  return view
end

return M
