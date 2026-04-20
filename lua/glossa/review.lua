local M = {}

function M.render_lines(entries)
  if #entries == 0 then
    return {
      "No cards are due right now.",
      "",
      "Run :GlossaLookup, then :GlossaSave to create your first card.",
    }
  end

  local lines = {
    ("Due cards: %d"):format(#entries),
  }

  for index, entry in ipairs(entries) do
    table.insert(lines, "")
    table.insert(lines, ("%d. %s"):format(index, entry.term or "(untitled)"))

    if entry.translation and entry.translation ~= "" then
      table.insert(lines, "   " .. entry.translation)
    end

    if entry.explanation and entry.explanation ~= "" then
      table.insert(lines, "   " .. entry.explanation)
    end
  end

  return lines
end

return M
