local M = {}
local config = require('github-projects.config')

-- Simple JSON decode function to avoid fast event context issues
local function safe_json_decode(json_str)
  if not json_str or json_str == "" then
    return nil, "Empty JSON"
  end

  -- Use vim.schedule to ensure we're in the right context
  local result = nil
  local error_msg = nil
  local completed = false

  vim.schedule(function()
    local success, parsed = pcall(vim.fn.json_decode, json_str)
    if success then
      result = parsed
    else
      error_msg = "JSON parse error: " .. tostring(parsed)
    end
    completed = true
  end)

  -- Wait for completion (this is not ideal, but works for our use case)
  local timeout = 0
  while not completed and timeout < 100 do
    vim.wait(10)
    timeout = timeout + 1
  end

  if completed then
    return result, error_msg
  else
    return nil, "Timeout parsing JSON"
  end
end

-- Alternative: Manual JSON parsing for GitHub responses
local function parse_github_json(json_str)
  local result = {}

  -- Handle GraphQL responses
  if json_str:match('"data"') and json_str:match('"organization"') then
    result.data = { organization = { projectsV2 = { nodes = {} } } }

    -- Extract projects using pattern matching
    local nodes = {}
    local in_nodes = false

    -- Look for the nodes array pattern
    for line in json_str:gmatch('[^\r\n]+') do
      if line:match('"nodes"') then
        in_nodes = true
      elseif in_nodes and line:match('"id"') then
        local id = line:match('"id":"([^"]+)"')
        local title = json_str:match('"id":"' .. (id or "") .. '"[^}]*"title":"([^"]+)"')
        local url = json_str:match('"id":"' .. (id or "") .. '"[^}]*"url":"([^"]+)"')
        local number = json_str:match('"id":"' .. (id or "") .. '"[^}]*"number":(%d+)')
        local shortDescription = json_str:match('"id":"' .. (id or "") .. '"[^}]*"shortDescription":"([^"]*)"')

        if id and title and url and number then
          table.insert(nodes, {
            id = id,
            title = title,
            url = url,
            number = tonumber(number),
            shortDescription = shortDescription ~= "" and shortDescription or nil
          })
        end
      end
    end

    result.data.organization.projectsV2.nodes = nodes
  end

  -- Check for errors
  if json_str:match('"errors"') then
    result.errors = {}
    for error_msg in json_str:gmatch('"message":"([^"]+)"') do
      table.insert(result.errors, { message = error_msg })
    end
  end

  -- Handle REST API responses (arrays)
  if json_str:match('^%s*%[') then
    result = {}
    -- This is likely an array response (repositories, issues, etc.)
    -- For now, we'll use a simple approach
    local items = {}

    -- Extract individual objects from array
    for item_str in json_str:gmatch('{[^{}]*}') do
      local item = {}

      -- Extract common fields
      item.id = item_str:match('"id":(%d+)')
      item.name = item_str:match('"name":"([^"]+)"')
      item.title = item_str:match('"title":"([^"]+)"')
      item.html_url = item_str:match('"html_url":"([^"]+)"')
      item.url = item_str:match('"url":"([^"]+)"')
      item.number = item_str:match('"number":(%d+)')
      item.state = item_str:match('"state":"([^"]+)"')
      item.description = item_str:match('"description":"([^"]*)"')
      item.language = item_str:match('"language":"([^"]*)"')
      item.stargazers_count = item_str:match('"stargazers_count":(%d+)')
      item.private = item_str:match('"private":(true|false)') == "true"

      -- Convert string numbers to actual numbers
      if item.id then item.id = tonumber(item.id) end
      if item.number then item.number = tonumber(item.number) end
      if item.stargazers_count then item.stargazers_count = tonumber(item.stargazers_count) end

      if item.name or item.title then
        table.insert(items, item)
      end
    end

    return items
  end

  return result
end

local function curl_request(url, headers, data, callback)
  local cmd = { "curl", "-s", "-w", "\\n%{http_code}" }

  for _, header in ipairs(headers or {}) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  if data then
    table.insert(cmd, "-X")
    table.insert(cmd, "POST")
    table.insert(cmd, "-d")
    table.insert(cmd, data)
  end

  table.insert(cmd, url)

  vim.system(cmd, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("Erro na requisição curl: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
      end)
      callback(nil, "Erro na requisição")
      return
    end

    local output = result.stdout
    if not output or output == "" then
      callback(nil, "Resposta vazia")
      return
    end

    -- Separar a resposta do código de status
    local lines = vim.split(output, "\n")
    local status_code = lines[#lines]
    local json_lines = {}

    for i = 1, #lines - 1 do
      if lines[i] and lines[i] ~= "" then
        table.insert(json_lines, lines[i])
      end
    end

    local json_data = table.concat(json_lines, "\n")

    if status_code ~= "200" then
      vim.schedule(function()
        vim.notify("HTTP Error " .. status_code .. ": " .. (json_data or ""), vim.log.levels.ERROR)
      end)
      callback(nil, "HTTP " .. status_code)
      return
    end

    if not json_data or json_data == "" then
      callback(nil, "JSON vazio")
      return
    end

    -- Use our custom JSON parser to avoid fast event context issues
    local parsed = parse_github_json(json_data)
    if parsed then
      callback(parsed, nil)
    else
      vim.schedule(function()
        vim.notify("Erro ao parsear JSON", vim.log.levels.ERROR)
      end)
      callback(nil, "Erro ao parsear JSON")
    end
  end)
end

function M.get_projects(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.schedule(function()
      vim.notify("Organização ou token não configurados", vim.log.levels.ERROR)
    end)
    callback(nil)
    return
  end

  -- Simplified GraphQL query
  local query_str = string.format(
    [[{"query": "query { organization(login: \"%s\") { projectsV2(first: 10) { nodes { id title url number shortDescription } } } }"}]],
    org)

  local headers = {
    "Authorization: Bearer " .. token,
    "Content-Type: application/json",
    "Accept: application/vnd.github.v3+json"
  }

  curl_request("https://api.github.com/graphql", headers, query_str, function(data, error)
    if error then
      vim.schedule(function()
        vim.notify("Erro ao carregar projetos: " .. error, vim.log.levels.ERROR)
      end)
      callback(nil)
      return
    end

    if data and data.errors then
      local error_msg = "Erro GraphQL: "
      for _, err in ipairs(data.errors) do
        error_msg = error_msg .. err.message .. " "
      end
      vim.schedule(function()
        vim.notify(error_msg, vim.log.levels.ERROR)
      end)
      callback(nil)
      return
    end

    if data and data.data and data.data.organization and data.data.organization.projectsV2 then
      local projects = data.data.organization.projectsV2.nodes
      if #projects > 0 then
        callback(projects)
      else
        vim.schedule(function()
          vim.notify("Nenhum projeto V2 encontrado na organização " .. org, vim.log.levels.WARN)
        end)
        callback({})
      end
    else
      vim.schedule(function()
        vim.notify("Organização não encontrada ou sem projetos V2", vim.log.levels.WARN)
      end)
      callback({})
    end
  end)
end

function M.get_issues(repo, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    callback(nil)
    return
  end

  local url
  if repo and repo ~= "" then
    url = string.format("https://api.github.com/repos/%s/%s/issues?state=all&per_page=50", org, repo)
  else
    url = string.format("https://api.github.com/search/issues?q=org:%s&per_page=50", org)
  end

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github.v3+json",
    "User-Agent: github-projects-nvim"
  }

  curl_request(url, headers, nil, function(data, error)
    if error then
      vim.schedule(function()
        vim.notify("Erro ao carregar issues: " .. error, vim.log.levels.ERROR)
      end)
      callback(nil)
      return
    end

    if data then
      local issues = data.items or data
      callback(issues)
    else
      callback({})
    end
  end)
end

function M.create_issue(issue_data, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token or not issue_data.repo then
    callback(false)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/issues", org, issue_data.repo)

  -- Manual JSON encoding to avoid vim.fn.json_encode in callback
  local json_body = string.format([[{"title": "%s", "body": "%s"}]],
    issue_data.title:gsub('"', '\\"'),
    (issue_data.body or ""):gsub('"', '\\"'))

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github.v3+json",
    "Content-Type: application/json",
    "User-Agent: github-projects-nvim"
  }

  curl_request(url, headers, json_body, function(result, error)
    if error then
      vim.schedule(function()
        vim.notify("Erro ao criar issue: " .. error, vim.log.levels.ERROR)
      end)
      callback(false)
      return
    end

    callback(result ~= nil)
  end)
end

function M.get_repositories(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org then
    callback(nil)
    return
  end

  local url = string.format("https://api.github.com/orgs/%s/repos?per_page=100&sort=updated", org)

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github.v3+json",
    "User-Agent: github-projects-nvim"
  }

  curl_request(url, headers, nil, function(data, error)
    if error then
      vim.schedule(function()
        vim.notify("Erro ao carregar repositórios: " .. error, vim.log.levels.ERROR)
      end)
      callback(nil)
      return
    end

    if data then
      callback(data)
    else
      callback({})
    end
  end)
end

function M.test_connection(callback)
  local token = config.get_token()

  if not token then
    callback(false, "Token não configurado")
    return
  end

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github.v3+json",
    "User-Agent: github-projects-nvim"
  }

  curl_request("https://api.github.com/user", headers, nil, function(data, error)
    if error then
      callback(false, error)
    else
      local login = "Unknown"
      if data and type(data) == "table" then
        -- Try to extract login from parsed data
        for k, v in pairs(data) do
          if k == "login" then
            login = v
            break
          end
        end
      end
      callback(true, "Conectado como: " .. login)
    end
  end)
end

return M
