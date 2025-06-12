local M = {}
local config = require('github-projects.config')

-- Função melhorada para parsing de JSON do GitHub
local function parse_github_json(json_str)
  if not json_str or json_str == "" then
    return nil
  end

  -- Tentar usar vim.json.decode primeiro (mais confiável)
  local success, result = pcall(vim.json.decode, json_str)
  if success then
    return result
  end

  -- Fallback para parsing manual se vim.json falhar
  local parsed = {}

  -- Para GraphQL responses
  if json_str:match('"data"') and json_str:match('"organization"') then
    parsed.data = { organization = { projectsV2 = { nodes = {} } } }

    -- Extrair projetos usando pattern matching mais robusto
    local projects = {}

    -- Pattern mais flexível para capturar projetos
    for project_block in json_str:gmatch('{[^{}]*"id"[^{}]*"title"[^{}]*"url"[^{}]*"number"[^{}]*}') do
      local id = project_block:match('"id"%s*:%s*"([^"]+)"')
      local title = project_block:match('"title"%s*:%s*"([^"]+)"')
      local url = project_block:match('"url"%s*:%s*"([^"]+)"')
      local number = project_block:match('"number"%s*:%s*(%d+)')
      local shortDescription = project_block:match('"shortDescription"%s*:%s*"([^"]*)"')

      if id and title and url and number then
        table.insert(projects, {
          id = id,
          title = title,
          url = url,
          number = tonumber(number),
          shortDescription = shortDescription ~= "" and shortDescription or nil
        })
      end
    end

    parsed.data.organization.projectsV2.nodes = projects
  end

  -- Verificar erros
  if json_str:match('"errors"') then
    parsed.errors = {}
    for error_msg in json_str:gmatch('"message"%s*:%s*"([^"]+)"') do
      table.insert(parsed.errors, { message = error_msg })
    end
  end

  return parsed
end

local function curl_request(url, headers, data, callback)
  local cmd = { "curl", "-s", "-w", "\\n%{http_code}" }

  -- Adicionar headers
  for _, header in ipairs(headers or {}) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  -- Adicionar dados se for POST
  if data then
    table.insert(cmd, "-X")
    table.insert(cmd, "POST")
    table.insert(cmd, "-d")
    table.insert(cmd, data)
  end

  table.insert(cmd, url)

  vim.system(cmd, {}, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Erro na requisição curl: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
        callback(nil, "Erro na requisição")
        return
      end

      local output = result.stdout
      if not output or output == "" then
        vim.notify("Resposta vazia da API", vim.log.levels.ERROR)
        callback(nil, "Resposta vazia")
        return
      end

      -- Separar resposta do código HTTP
      local lines = vim.split(output, "\n")
      local status_code = lines[#lines]
      local json_lines = {}

      for i = 1, #lines - 1 do
        if lines[i] and lines[i] ~= "" then
          table.insert(json_lines, lines[i])
        end
      end

      local json_data = table.concat(json_lines, "\n")

      -- Debug: mostrar resposta da API
      print("Status code:", status_code)
      print("JSON response:", json_data:sub(1, 200) .. "...")

      if status_code ~= "200" then
        vim.notify("HTTP Error " .. status_code .. ": " .. (json_data or ""), vim.log.levels.ERROR)
        callback(nil, "HTTP " .. status_code)
        return
      end

      if not json_data or json_data == "" then
        vim.notify("JSON vazio na resposta", vim.log.levels.ERROR)
        callback(nil, "JSON vazio")
        return
      end

      -- Parsing do JSON
      local parsed = parse_github_json(json_data)
      if parsed then
        callback(parsed, nil)
      else
        vim.notify("Erro ao parsear JSON da resposta", vim.log.levels.ERROR)
        callback(nil, "Erro ao parsear JSON")
      end
    end)
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

  -- Query GraphQL mais robusta
  local query = {
    query = string.format([[
      query {
        organization(login: "%s") {
          projectsV2(first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) {
            nodes {
              id
              title
              url
              number
              shortDescription
              updatedAt
              createdAt
            }
          }
        }
      }
    ]], org)
  }

  local query_json = vim.json.encode(query)

  local headers = {
    "Authorization: Bearer " .. token,
    "Content-Type: application/json",
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28"
  }

  print("Fazendo requisição para projetos da organização:", org)

  curl_request("https://api.github.com/graphql", headers, query_json, function(data, error)
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
      local projects = data.data.organization.projectsV2.nodes
      print("Projetos encontrados:", #projects)
      if #projects > 0 then
        callback(projects)
      else
        vim.notify("Nenhum projeto V2 encontrado na organização " .. org, vim.log.levels.WARN)
        callback({})
      end
    else
      vim.notify("Organização não encontrada ou sem projetos V2", vim.log.levels.WARN)
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
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28",
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

  local json_body = vim.json.encode({
    title = issue_data.title,
    body = issue_data.body or ""
  })

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github+json",
    "Content-Type: application/json",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  curl_request(url, headers, json_body, function(result, error)
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

  if not org then
    callback(nil)
    return
  end

  local url = string.format("https://api.github.com/orgs/%s/repos?per_page=100&sort=updated", org)

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28",
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
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  curl_request("https://api.github.com/user", headers, nil, function(data, error)
    if error then
      callback(false, error)
    else
      local login = data and data.login or "Unknown"
      callback(true, "Conectado como: " .. login)
    end
  end)
end

return M
