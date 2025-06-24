local M = {}

-- Simple in-memory cache
local cache = {}
local cache_ttl = 300 -- 5 minutes

-- Cache key generator
local function generate_key(...)
  return table.concat({ ... }, "_")
end

-- Check if cache entry is valid
local function is_valid(entry)
  if not entry then return false end
  return os.time() - entry.timestamp < cache_ttl
end

-- Get from cache
function M.get(...)
  local key = generate_key(...)
  local entry = cache[key]

  if is_valid(entry) then
    return entry.data
  end

  return nil
end

-- Set cache
function M.set(data, ...)
  local key = generate_key(...)
  cache[key] = {
    data = data,
    timestamp = os.time()
  }
end

-- Clear cache
function M.clear()
  cache = {}
end

-- Clear specific cache entry
function M.clear_key(...)
  local key = generate_key(...)
  cache[key] = nil
end

return M
