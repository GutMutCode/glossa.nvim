local M = {}

local function default_data()
  return {
    version = 1,
    entries = {},
  }
end

local function ensure_parent_dir(path)
  local parent = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(parent, "p")
end

local function normalize_data(decoded)
  if type(decoded) ~= "table" then
    return default_data()
  end

  if vim.islist(decoded) then
    return {
      version = 1,
      entries = decoded,
    }
  end

  if not vim.islist(decoded.entries) then
    decoded.entries = {}
  end

  if type(decoded.version) ~= "number" then
    decoded.version = 1
  end

  return decoded
end

local function read_data(path)
  if vim.fn.filereadable(path) == 0 then
    return default_data()
  end

  local raw = table.concat(vim.fn.readfile(path), "\n")
  if raw == "" then
    return default_data()
  end

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    vim.notify(
      ("Could not decode glossa data: %s"):format(path),
      vim.log.levels.ERROR,
      { title = "glossa.nvim" }
    )
    return default_data()
  end

  return normalize_data(decoded)
end

local function write_data(path, data)
  ensure_parent_dir(path)
  vim.fn.writefile({ vim.json.encode(data) }, path)
end

local function entry_key(entry)
  return table.concat({
    entry.term or "",
    entry.source_lang or "",
    entry.target_lang or "",
  }, "::")
end

local function normalize_entry(entry)
  local saved_at = os.time()

  return vim.tbl_deep_extend("force", {
    review_count = 0,
    interval = 1,
    next_review_at = saved_at,
    saved_at = saved_at,
  }, entry)
end

function M.save_entry(path, entry)
  local data = read_data(path)
  local normalized = normalize_entry(entry)
  local index_to_replace = nil

  for index, existing in ipairs(data.entries) do
    if entry_key(existing) == entry_key(normalized) then
      index_to_replace = index
      break
    end
  end

  if index_to_replace then
    data.entries[index_to_replace] = normalized
  else
    table.insert(data.entries, 1, normalized)
  end

  write_data(path, data)

  return {
    count = #data.entries,
  }
end

function M.list_due(path)
  local data = read_data(path)
  local now = os.time()
  local due = {}

  for _, entry in ipairs(data.entries) do
    if (entry.next_review_at or 0) <= now then
      table.insert(due, entry)
    end
  end

  return due
end

function M.stats(path)
  local data = read_data(path)
  local due = M.list_due(path)

  return {
    total = #data.entries,
    due = #due,
  }
end

return M
