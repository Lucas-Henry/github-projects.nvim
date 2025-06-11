local M = {}
local config = require('github-projects.config')

-- Executar comando curl e parsear JSON
local function curl_request(url, headers, data, callback)
  local cmd = { "curl", "-s", "-w", "%{http_code}" }

  -- Adicionar headers
  for _, header in ipairs(headers or {}) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  -- Adicionar dados se POST
  if data then
    table.insert(cmd, "-X")
    table.insert(cmd, "POST")
    table.insert(cmd, "-d")
    table.insert(cmd, data)
  end

  table.insert(cmd, url)

  vim.system(cmd, {}, function(result)
    if result.code ~= 0 then
      callback(nil, "Erro na requisição")
      return
    end

    local output = result.stdout
    local status_code = output:match("(%d+)$")
    local json_data = output:gsub("%d+$", "")

    if status_code ~= "200" then
      callback(nil, "HTTP " .. status_code)
      return
    end

    local success, parsed = pcall(vim.fn.json_decode, json_data)
    if success then
      callback(parsed, nil)
    else
      callback(nil, "Erro ao parsear JSON")
    end
  end)
end

-- Obter projetos V2 via GraphQL
function M.get_projects(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    callback(nil)
    return
  end

  local query = string.format([[
    {
      "query": "query { organization(login: \"%s\") { projectsV2(first: 20) { nodes { id title url description } } } }"
    }
  ]], org)

  local headers = {
    "Authorization: token " .. token,
    "Content-Type: application/json"
  }

  curl_request("https://api.github.com/graphql", headers, query, function(data, error)
    if error then
      vim.notify("Erro ao carregar projetos: " .. error, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.data and data.data.organization and data.data.organization.projectsV2 then
      callback(data.data.organization.projectsV2.nodes)
    else
      callback({})
    end
  end)
end

-- Obter issues
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
    url = string.format("https://api.github.com/orgs/%s/issues?state=all&per_page=50", org)
  end

  local headers = {
    "Authorization: token " .. token,
    "Accept: application/vnd.github.v3+json"
  }

  curl_request(url, headers, nil, function(data, error)
    if error then
      vim.notify("Erro ao carregar issues: " .. error, vim.log.levels.ERROR)
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

-- Criar nova issue
function M.create_issue(issue_data, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token or not issue_data.repo then
    callback(false)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/issues", org, issue_data.repo)

  local data = vim.fn.json_encode({
    title = issue_data.title,
    body = issue_data.body or "",
    labels = issue_data.labels or {}
  })

  local headers = {
    "Authorization: token " .. token,
    "Accept: application/vnd.github.v3+json",
    "Content-Type: application/json"
  }

  curl_request(url, headers, data, function(result, error)
    if error then
      vim.notify("Erro ao criar issue: " .. error, vim.log.levels.ERROR)
      callback(false)
      return
    end

    callback(result ~= nil)
  end)
end

-- Obter repositórios
function M.get_repositories(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    callback(nil)
    return
  end

  local url = string.format("https://api.github.com/orgs/%s/repos?per_page=100", org)

  local headers = {
    "Authorization: token " .. token,
    "Accept: application/vnd.github.v3+json"
  }

  curl_request(url, headers, nil, function(data, error)
    if error then
      vim.notify("Erro ao carregar repositórios: " .. error, vim.log.levels.ERROR)
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

return M
