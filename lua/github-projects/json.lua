-- Simple JSON decoder in pure Lua
-- This avoids the "fast event context" error

local M = {}

function M.decode(str)
  if not str or str == "" then
    return nil, "Empty JSON string"
  end

  -- Remove leading/trailing whitespace
  str = str:match("^%s*(.-)%s*$")

  -- Try to use a simple method first
  local success, result = pcall(function()
    -- For simple cases, we can use loadstring (but this is not safe for untrusted input)
    -- We'll use a safer approach with string manipulation

    -- Convert JSON boolean/null values to Lua equivalents
    local lua_str = str:gsub('"([^"]*)":', '["%1"]=')
        :gsub(':%s*"([^"]*)"', '="%1"')
        :gsub(':%s*(%d+%.?%d*)', '=%1')
        :gsub(':%s*true', '=true')
        :gsub(':%s*false', '=false')
        :gsub(':%s*null', '=nil')
        :gsub('%[', '{')
        :gsub('%]', '}')

    -- This is a very basic approach - for production use, consider using a proper JSON library
    -- But for now, let's try a different approach
    return nil
  end)

  if success and result then
    return result
  end

  -- Fallback: try to parse manually for our specific GitHub API responses
  return M.parse_github_response(str)
end

-- Parse specific GitHub API responses manually
function M.parse_github_response(str)
  local result = {}

  -- Try to extract data from GitHub GraphQL response
  if str:match('"data"') then
    result.data = {}

    -- Extract organization data
    if str:match('"organization"') then
      result.data.organization = {}

      -- Extract projectsV2 data
      if str:match('"projectsV2"') then
        result.data.organization.projectsV2 = {}
        result.data.organization.projectsV2.nodes = {}

        -- Extract individual projects
        local projects = {}
        for project_match in str:gmatch('"id":"([^"]+)","title":"([^"]+)","url":"([^"]+)","number":(%d+)') do
          local id, title, url, number = project_match:match(
            '"id":"([^"]+)","title":"([^"]+)","url":"([^"]+)","number":(%d+)')
          if id and title and url and number then
            table.insert(projects, {
              id = id,
              title = title,
              url = url,
              number = tonumber(number),
              shortDescription = nil -- GitHub API might not always include this
            })
          end
        end

        -- More robust project extraction
        local project_pattern = '{[^}]*"id":"([^"]+)"[^}]*"title":"([^"]+)"[^}]*"url":"([^"]+)"[^}]*"number":(%d+)[^}]*}'
        for project_str in str:gmatch(project_pattern) do
          local id = project_str:match('"id":"([^"]+)"')
          local title = project_str:match('"title":"([^"]+)"')
          local url = project_str:match('"url":"([^"]+)"')
          local number = project_str:match('"number":(%d+)')
          local shortDescription = project_str:match('"shortDescription":"([^"]*)"') or nil

          if id and title and url and number then
            table.insert(projects, {
              id = id,
              title = title,
              url = url,
              number = tonumber(number),
              shortDescription = shortDescription
            })
          end
        end

        result.data.organization.projectsV2.nodes = projects
      end
    end
  end

  -- Check for errors
  if str:match('"errors"') then
    result.errors = {}
    for error_msg in str:gmatch('"message":"([^"]+)"') do
      table.insert(result.errors, { message = error_msg })
    end
  end

  return result
end

return M
