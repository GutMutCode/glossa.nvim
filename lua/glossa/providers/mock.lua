local M = {}

local function compact_text(text)
  return vim.trim((text or ""):gsub("%s+", " "))
end

function M.lookup(text, opts)
  local cleaned = compact_text(text)
  local is_phrase = cleaned:find("%s") ~= nil

  return {
    term = cleaned,
    source_text = text,
    source_lang = opts.source_lang,
    target_lang = opts.target_lang,
    kind = is_phrase and "phrase" or "word",
    translation = "Backend not connected yet.",
    explanation = table.concat({
      "This scaffold already supports capture, float display, save, and review.",
      "Replace the mock provider with a real dictionary or translation backend next.",
    }, " "),
    examples = {
      ("Captured from the current buffer: %s"):format(cleaned),
      "Try mapping <Plug>(GlossaLookup) and <Plug>(GlossaSave) in your config.",
    },
    notes = {
      "Provider module: lua/glossa/providers/mock.lua",
      "Storage path defaults to stdpath('data') .. '/glossa.nvim/cards.json'.",
    },
    looked_up_at = os.time(),
  }
end

return M
