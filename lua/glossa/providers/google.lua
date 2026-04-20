local M = {}

local DT_FIELDS = {
  "at",
  "bd",
  "ex",
  "ld",
  "md",
  "qca",
  "rw",
  "rm",
  "ss",
  "t",
}

local function compact_text(text)
  return vim.trim((text or ""):gsub("%s+", " "))
end

local function assert_curl()
  if vim.fn.executable("curl") == 1 then
    return
  end

  error("glossa.nvim google provider requires 'curl' in PATH", 0)
end

local function get_google_config(opts)
  local config = opts.google or {}
  return {
    endpoint = config.endpoint or "https://translate.googleapis.com/translate_a/single",
    timeout_ms = config.timeout_ms or 8000,
  }
end

local function build_command(text, opts, config)
  local command = {
    "curl",
    "-fsSLG",
    "--max-time",
    tostring(math.max(1, math.ceil(config.timeout_ms / 1000))),
    config.endpoint,
    "--data-urlencode",
    "client=gtx",
    "--data-urlencode",
    "sl=" .. (opts.source_lang or "auto"),
    "--data-urlencode",
    "tl=" .. (opts.target_lang or "ko"),
  }

  for _, field in ipairs(DT_FIELDS) do
    table.insert(command, "--data-urlencode")
    table.insert(command, "dt=" .. field)
  end

  table.insert(command, "--data-urlencode")
  table.insert(command, "q=" .. text)

  return command
end

local function decode_response(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout)
  if ok and type(decoded) == "table" then
    return decoded
  end

  error("glossa.nvim google provider received invalid JSON", 0)
end

local function get_paraphrase(response)
  local chunks = response[1]
  if type(chunks) ~= "table" then
    return nil
  end

  local parts = {}
  for _, chunk in ipairs(chunks) do
    if type(chunk) == "table" and type(chunk[1]) == "string" and chunk[1] ~= "" then
      table.insert(parts, chunk[1])
    end
  end

  if #parts == 0 then
    return nil
  end

  return table.concat(parts, "")
end

local function get_phonetic(response)
  local chunks = response[1]
  if type(chunks) ~= "table" then
    return nil
  end

  for _, chunk in ipairs(chunks) do
    if type(chunk) == "table" and type(chunk[4]) == "string" and chunk[4] ~= "" then
      return chunk[4]
    end
  end

  return nil
end

local function get_explanations(response)
  local dictionary = response[2]
  if type(dictionary) ~= "table" then
    return {}
  end

  local explanations = {}
  for _, entry in ipairs(dictionary) do
    local part_of_speech = entry[1]
    local terms = entry[2]

    if type(part_of_speech) == "string" and type(terms) == "table" then
      local words = {}
      for _, term in ipairs(terms) do
        if type(term) == "string" and term ~= "" then
          table.insert(words, term)
        end
      end

      if #words > 0 then
        table.insert(explanations, ("[%s] %s"):format(part_of_speech, table.concat(words, "; ")))
      end
    end
  end

  return explanations
end

local function get_examples(response)
  local definition_groups = response[13]
  if type(definition_groups) ~= "table" then
    return {}
  end

  local examples = {}
  for _, group in ipairs(definition_groups) do
    local part_of_speech = group[1]
    local definitions = group[2]

    if type(definitions) == "table" then
      for _, definition in ipairs(definitions) do
        local text = definition[1]
        local example = definition[3]

        if type(text) == "string" and text ~= "" then
          local line = type(part_of_speech) == "string" and ("[%s] %s"):format(part_of_speech, text)
            or text
          if type(example) == "string" and example ~= "" then
            line = line .. " Example: " .. example
          end
          table.insert(examples, line)
          if #examples >= 5 then
            return examples
          end
        end
      end
    end
  end

  return examples
end

local function get_alternatives(response, translation)
  local alternatives = response[6]
  if type(alternatives) ~= "table" then
    return {}
  end

  local result = {}
  local seen = {}

  for _, entry in ipairs(alternatives) do
    local words = entry[3]
    if type(words) == "table" then
      for _, word in ipairs(words) do
        local alternative = word[1]
        if type(alternative) == "string" and alternative ~= "" and alternative ~= translation and not seen[alternative] then
          seen[alternative] = true
          table.insert(result, alternative)
          if #result >= 5 then
            return result
          end
        end
      end
    end
  end

  return result
end

local function build_entry(text, opts, response)
  local cleaned = compact_text(text)
  local translation = get_paraphrase(response)
  local detected_source_lang = type(response[3]) == "string" and response[3] or opts.source_lang
  local notes = {
    "Provider: google (translate.googleapis.com)",
  }

  if opts.source_lang == "auto" and detected_source_lang and detected_source_lang ~= "auto" then
    table.insert(notes, "Detected language: " .. detected_source_lang)
  end

  return {
    term = cleaned,
    source_text = text,
    source_lang = detected_source_lang,
    target_lang = opts.target_lang,
    kind = cleaned:find("%s") ~= nil and "phrase" or "word",
    phonetic = get_phonetic(response),
    translation = translation or "(no translation returned)",
    explanation = get_explanations(response),
    examples = get_examples(response),
    alternatives = get_alternatives(response, translation),
    notes = notes,
    looked_up_at = os.time(),
  }
end

local function parse_output(stdout, text, opts)
  return build_entry(text, opts, decode_response(stdout))
end

function M.lookup(text, opts)
  assert_curl()

  local config = get_google_config(opts)
  local command = build_command(text, opts, config)
  local result = vim.system(command, { text = true }):wait(config.timeout_ms)

  if result.code ~= 0 then
    local message = result.stderr ~= "" and vim.trim(result.stderr)
      or "curl exited with a non-zero status"
    error(("glossa.nvim google provider failed: %s"):format(message), 0)
  end

  return parse_output(result.stdout, text, opts)
end

function M.lookup_async(text, opts, callback)
  assert_curl()

  local config = get_google_config(opts)
  local command = build_command(text, opts, config)

  return vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = result.stderr ~= "" and vim.trim(result.stderr)
          or "curl exited with a non-zero status"
        callback(("glossa.nvim google provider failed: %s"):format(message))
        return
      end

      local ok, entry = pcall(parse_output, result.stdout, text, opts)
      if not ok then
        callback(entry)
        return
      end

      callback(nil, entry)
    end)
  end)
end

return M
