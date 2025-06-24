local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Enhanced UI with fullscreen support and markdown rendering
local popup = require('nui.popup')
local layout = require('nui.layout')
local text = require('nui.text')

-- Helper for safe string conversion (moved from ui_nui.lua)
local function safe_str(value)
  if value == nil or value == vim.NIL then
    return ""
  end
  if type(value) == "string" then
    return value
  end
  return tostring(value)
end

-- Markdown renderer (basic implementation)
local function render_markdown_line(line)
  -- Basic markdown parsing
  if line:match("^#+ ") then
    -- Headers
    local level = #line:match("^(#+)")
    local text = line:gsub("^#+ ", "")
    return text, "GitHubProjectsMarkdownHeader" .. level
  elseif line:match("^%s*%- ") or line:match("^%s*%* ") then
    -- Lists
    return line, "GitHubProjectsMarkdownList"
  elseif line:match("^```") then
    -- Code blocks
    return line, "GitHubProjectsMarkdownCode"
  elseif line:match("^> ") then
    -- Quotes
    return line, "GitHubProjectsMarkdownQuote"
  else
    return line, "Normal"
  end
end

-- Create fullscreen issue viewer with markdown support
function M.show_issue_fullscreen(issue)
  local lines = {}
  local highlights = {}

  -- Parse issue body with markdown
  local body_lines = vim.split(safe_str(issue.body) or "No description.", "\n")
  for i, line in ipairs(body_lines) do
    local rendered_line, highlight = render_markdown_line(line)
    table.insert(lines, rendered_line)
    table.insert(highlights, { line = i - 1, highlight = highlight })
  end

  -- Create fullscreen popup
  local issue_popup = popup({
    position = "50%",
    size = "100%",
    border = {
      style = "rounded",
      text = {
        top = "Issue #" .. safe_str(issue.number) .. ": " .. safe_str(issue.title),
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
    },
    buf_options = {
      modifiable = true,
    },
  })

  issue_popup:mount()

  -- Set buffer content
  local bufnr = issue_popup.bufnr
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsMarkdown")
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl.highlight, hl.line, 0, -1)
  end

  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', true)

  -- Keymaps
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q',
    ":lua require('nui.popup').close()<CR>",
    { noremap = true, silent = true })

  return issue_popup
end

-- Enhanced issue creation with project board selection
function M.create_issue_with_project_selection(callback)
  -- First get all projects
  vim.notify("Loading projects...", vim.log.levels.INFO)
  api.get_projects(function(projects)
    if not projects or #projects == 0 then
      -- Fallback to regular issue creation
      require('github-projects.ui_nui').create_issue_form(callback)
      return
    end

    -- Add "No Project Board" option
    local project_options = { { title = "No Project Board", value = nil } }
    for _, project in ipairs(projects) do
      table.insert(project_options, {
        title = safe_str(project.title) .. " (#" .. safe_str(project.number) .. ")",
        value = project
      })
    end

    vim.ui.select(project_options, {
      prompt = "Select Project Board (optional):",
      format_item = function(item) return item.title end,
    }, function(selected_project_option)
      if not selected_project_option then
        vim.notify("Issue creation canceled.", vim.log.levels.INFO)
        return
      end

      local selected_project = selected_project_option.value

      if not selected_project then
        -- Create regular issue without project
        require('github-projects.ui_nui').create_issue_form(callback)
        return
      end

      -- Get project details to show status options
      vim.notify("Loading project details...", vim.log.levels.INFO)
      api.get_project_details(selected_project.number, function(project_data)
        if not project_data then
          vim.notify("Error loading project details", vim.log.levels.ERROR)
          return
        end

        local status_options = {}
        for _, status in ipairs(project_data.statuses) do
          table.insert(status_options, {
            title = safe_str(status.name),
            value = status
          })
        end

        if #status_options == 0 then
          vim.notify("No status columns found in project", vim.log.levels.WARN)
          -- Fallback to regular issue creation
          require('github-projects.ui_nui').create_issue_form(callback)
          return
        end

        vim.ui.select(status_options, {
          prompt = "Select Status Column:",
          format_item = function(item) return item.title end,
        }, function(selected_status)
          if not selected_status then
            vim.notify("Issue creation canceled.", vim.log.levels.INFO)
            return
          end

          -- Now create issue form with project context
          M._create_issue_form_with_context(selected_project, selected_status.value, callback)
        end)
      end)
    end)
  end)
end

function M._create_issue_form_with_context(project, status, callback)
  vim.notify("Loading repositories...", vim.log.levels.INFO)
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("No repositories found", vim.log.levels.ERROR)
      return
    end

    local repo_names = {}
    for _, repo in ipairs(repos) do
      local repo_name = safe_str(repo.name)
      if repo_name ~= "" then
        table.insert(repo_names, repo_name)
      end
    end

    vim.ui.select(repo_names, {
      prompt = "Select Repository:",
      format_item = function(item) return item end,
    }, function(selected_repo)
      if not selected_repo then
        vim.notify("Issue creation canceled.", vim.log.levels.INFO)
        return
      end

      vim.ui.input({ prompt = "Issue Title: " }, function(issue_title)
        if not issue_title or issue_title == "" then
          vim.notify("Title is required. Issue creation canceled.", vim.log.levels.ERROR)
          return
        end

        vim.ui.input({ prompt = "Description (optional): " }, function(issue_body)
          callback({
            repo = selected_repo,
            title = issue_title,
            body = issue_body or "",
            project = project,
            status = status
          })
        end)
      end)
    end)
  end)
end

return M
