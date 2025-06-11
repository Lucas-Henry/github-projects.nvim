local M = {}
local config = require('github-projects.config')

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
      vim.notify("Erro na requisição curl: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
      callback(nil, "Erro na requisição")
      return
    end

    local output = result.stdout
    if not output or output == "" then
      callback(nil, "Resposta vazia")
      return
    end

    local lines = vim.split(output, "\n")
    local status_code = lines[#lines] -- Última linha
    local json_lines = {}

    for i = 1, #lines - 1 do
      if lines[i] and lines[i] ~= "" then
        table.insert(json_lines, lines[i])
      end
    end

    local json_data = table.concat(json_lines, "\n")

    print("Status Code:", status_code)
    print("JSON Data (first 200 chars):", string.sub(json_data or "", 1, 200))

    if status_code ~= "200" then
      vim.notify("HTTP Error " .. status_code .. ": " .. (json_data or ""), vim.log.levels.ERROR)
      callback(nil, "HTTP " .. status_code)
      return
    end

    if not json_data or json_data == "" then
      callback(nil, "JSON vazio")
      return
    end

    local success, parsed = pcall(vim.fn.json_decode, json_data)
    if success then
      callback(parsed, nil)
    else
      vim.notify("Erro ao parsear JSON. Dados recebidos: " .. string.sub(json_data, 1, 500), vim.log.levels.ERROR)
      callback(nil, "Erro ao parsear JSON: " .. tostring(parsed))
    end
  end)
end

function M.get_projects(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("Organização ou token não configurados", vim.log.levels.ERROR)
    callback(nil)
    return
  end

  local query = string.format([[{
    "query": "query { organization(login: \"%s\") { projectsV2(first: 10) { nodes { id title url description } } } }"
  }]], org)

  local headers = {
    "Authorization: Bearer " .. token, -- Mudança: Bearer ao invés de token
    "Content-Type: application/json",
    "Accept: application/vnd.github.v3+json"
  }

  print("Fazendo requisição para projetos da org:", org)

  curl_request("https://api.github.com/graphql", headers, query, function(data, error)
    if error then
      vim.notify("Erro ao carregar projetos: " .. error, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.errors then
      local error_msg = "Erro GraphQL: "
      for _, err in ipairs(data.errors) do
        error_msg = error_msg .. err.message .. " "
      end
      vim.notify(error_msg, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.data and data.data.organization and data.data.organization.projectsV2 then
      callback(data.data.organization.projectsV2.nodes)
    else
      vim.notify("Nenhum projeto V2 encontrado, tentando repositórios...", vim.log.levels.WARN)
      M.get_repositories(callback)
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
      vim.notify("Erro ao carregar issues: " .. error, vim.log.levels.ERROR)
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

  local data = vim.fn.json_encode({
    title = issue_data.title,
    body = issue_data.body or "",
    labels = issue_data.labels or {}
  })

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github.v3+json",
    "Content-Type: application/json",
    "User-Agent: github-projects-nvim"
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

function M.get_repositories(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
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
      callback(true, "Conectado como: " .. (data.login or "Unknown"))
    end
  end)
end

return M
