local M = {}
local config = require('github-projects.config')

-- Parse GitHub JSON response
local function parse_github_json(json_str)
  if not json_str or json_str == "" then
    return nil
  end

  local success, result = pcall(vim.json.decode, json_str)
  if success then
    return result
  end

  return nil
end

-- Make a curl request
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
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Curl request error: " .. (result.stderr or "Unknown error"), vim.log.levels.ERROR)
        callback(nil, "Request error")
        return
      end

      local output = result.stdout
      if not output or output == "" then
        vim.notify("Empty API response", vim.log.levels.ERROR)
        callback(nil, "Empty response")
        return
      end

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
        vim.notify("HTTP Error " .. status_code .. ": " .. (json_data or ""), vim.log.levels.ERROR)
        callback(nil, "HTTP " .. status_code)
        return
      end

      if not json_data or json_data == "" then
        vim.notify("Empty JSON response", vim.log.levels.ERROR)
        callback(nil, "Empty JSON")
        return
      end

      local parsed = parse_github_json(json_data)
      if parsed then
        callback(parsed, nil)
      else
        vim.notify("Error parsing JSON response", vim.log.levels.ERROR)
        callback(nil, "JSON parse error")
      end
    end)
  end)
end

-- Get projects
function M.get_projects(callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("Organization or token not configured", vim.log.levels.ERROR)
    callback(nil)
    return
  end

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

  curl_request("https://api.github.com/graphql", headers, query_json, function(data, error)
    if error then
      vim.notify("Error loading projects: " .. error, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.errors then
      local error_msg = "GraphQL Error: "
      for _, err in ipairs(data.errors) do
        error_msg = error_msg .. err.message .. " "
      end
      vim.notify(error_msg, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.data and data.data.organization and data.data.organization.projectsV2 then
      local projects = data.data.organization.projectsV2.nodes
      if #projects > 0 then
        callback(projects)
      else
        vim.notify("No V2 projects found in organization " .. org, vim.log.levels.WARN)
        callback({})
      end
    else
      vim.notify("Organization not found or has no V2 projects", vim.log.levels.WARN)
      callback({})
    end
  end)
end

-- Get project details with custom fields and statuses
function M.get_project_details(project_number, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    callback(nil)
    return
  end

  local query = {
    query = string.format([[
    query {
      organization(login: "%s") {
        projectV2(number: %d) {
          id
          title
          shortDescription
          fields(first: 20) {
            nodes {
              ... on ProjectV2SingleSelectField {
                id
                name
                options {
                  id
                  name
                  color
                }
              }
            }
          }
          items(first: 100) {
            nodes {
              id
              fieldValues(first: 20) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                    field {
                      ... on ProjectV2FieldCommon {
                        name
                      }
                    }
                  }
                }
              }
              content {
                ... on Issue {
                  id
                  number
                  title
                  state
                  body
                  url
                  repository {
                    name
                  }
                  labels(first: 10) {
                    nodes {
                      name
                      color
                    }
                  }
                  assignees(first: 5) {
                    nodes {
                      login
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ]], org, project_number)
  }

  local query_json = vim.json.encode(query)

  local headers = {
    "Authorization: Bearer " .. token,
    "Content-Type: application/json",
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28"
  }

  curl_request("https://api.github.com/graphql", headers, query_json, function(data, error)
    if error then
      vim.notify("Error loading project details: " .. error, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.errors then
      local error_msg = "GraphQL Error: "
      for _, err in ipairs(data.errors) do
        error_msg = error_msg .. err.message .. " "
      end
      vim.notify(error_msg, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if data and data.data and data.data.organization and data.data.organization.projectV2 then
      local project = data.data.organization.projectV2

      -- Process project data to extract status field and organize issues by status
      local status_field = nil
      local statuses = {}
      local issues_by_status = {}
      local default_statuses = { "Todo", "In Progress", "Done" }

      -- Find status field (usually "Status" or similar)
      for _, field in ipairs(project.fields.nodes or {}) do
        if field.options and (field.name == "Status" or field.name:lower():match("status")) then
          status_field = field
          break
        end
      end

      -- Extract available statuses
      if status_field and status_field.options then
        for _, option in ipairs(status_field.options) do
          table.insert(statuses, {
            id = option.id,
            name = option.name,
            color = option.color
          })
          issues_by_status[option.name] = {}
        end
      else
        -- Fallback to default statuses
        for _, status in ipairs(default_statuses) do
          table.insert(statuses, {
            id = status,
            name = status,
            color = status == "Todo" and "YELLOW" or (status == "In Progress" and "BLUE" or "GREEN")
          })
          issues_by_status[status] = {}
        end

        -- Also add Open/Closed as fallback
        issues_by_status["Open"] = {}
        issues_by_status["Closed"] = {}
      end

      -- Process items and assign to statuses
      for _, item in ipairs(project.items.nodes or {}) do
        if item.content then
          local issue = item.content
          local issue_status = nil

          -- Try to find status from field values
          for _, fieldValue in ipairs(item.fieldValues.nodes or {}) do
            if fieldValue.field and fieldValue.field.name and
                (fieldValue.field.name == "Status" or fieldValue.field.name:lower():match("status")) then
              issue_status = fieldValue.name
              break
            end
          end

          -- If no status found, use issue state
          if not issue_status then
            issue_status = issue.state == "OPEN" and "Open" or "Closed"
          end

          -- Ensure the status exists in our map
          if not issues_by_status[issue_status] then
            issues_by_status[issue_status] = {}
          end

          -- Add issue to the appropriate status
          table.insert(issues_by_status[issue_status], {
            id = issue.id,
            number = issue.number,
            title = issue.title,
            body = issue.body,
            state = issue.state,
            url = issue.url,
            html_url = issue.url,
            repository = issue.repository and issue.repository.name or nil,
            labels = issue.labels and issue.labels.nodes or {},
            assignees = issue.assignees and issue.assignees.nodes or {},
            status = issue_status
          })
        end
      end

      callback({
        project = project,
        statuses = statuses,
        issues_by_status = issues_by_status
      })
    else
      vim.notify("Project not found or has no items", vim.log.levels.WARN)
      callback(nil)
    end
  end)
end

-- Get issues (fallback method)
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
    url = string.format("https://api.github.com/search/issues?q=org:%s+is:issue&per_page=50", org)
  end

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  curl_request(url, headers, nil, function(data, error)
    if error then
      vim.notify("Error loading issues: " .. error, vim.log.levels.ERROR)
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

-- Update issue state
function M.update_issue_state(repo, issue_number, new_state, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token or not repo or not issue_number or not new_state then
    callback(false)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/issues/%d", org, repo, issue_number)

  local json_body = vim.json.encode({
    state = new_state
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
      vim.notify("Error updating issue: " .. error, vim.log.levels.ERROR)
      callback(false)
      return
    end
    callback(result ~= nil)
  end)
end

-- Create issue
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
      vim.notify("Error creating issue: " .. error, vim.log.levels.ERROR)
      callback(false)
      return
    end

    callback(result ~= nil)
  end)
end

-- Get repositories
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
      vim.notify("Error loading repositories: " .. error, vim.log.levels.ERROR)
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

-- Test connection
function M.test_connection(callback)
  local token = config.get_token()

  if not token then
    callback(false, "Token not configured")
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
      callback(true, "Connected as: " .. login)
    end
  end)
end

return M
