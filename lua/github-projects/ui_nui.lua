local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Import nui.nvim modules
local popup = require('nui.popup')
local menu = require('nui.menu')

-- UI manager
local GitHubProjectsNuiUI = {}
GitHubProjectsNuiUI.current_popup = nil
GitHubProjectsNuiUI.current_menu = nil
GitHubProjectsNuiUI.issue_map = {}
GitHubProjectsNuiUI.current_column = 1
GitHubProjectsNuiUI.current_selection = 1
GitHubProjectsNuiUI.columns = {}
GitHubProjectsNuiUI.issues_by_column = {}
GitHubProjectsNuiUI.current_project = nil
GitHubProjectsNuiUI.previous_view = nil

-- Close current popup
function GitHubProjectsNuiUI.close_current_popup()
  if GitHubProjectsNuiUI.current_popup then
    GitHubProjectsNuiUI.current_popup:unmount()
    GitHubProjectsNuiUI.current_popup = nil
  end
  if GitHubProjectsNuiUI.current_menu then
    GitHubProjectsNuiUI.current_menu:unmount()
    GitHubProjectsNuiUI.current_menu = nil
  end
  GitHubProjectsNuiUI.issue_map = {}
  GitHubProjectsNuiUI.current_column = 1
  GitHubProjectsNuiUI.current_selection = 1
  GitHubProjectsNuiUI.columns = {}
  GitHubProjectsNuiUI.issues_by_column = {}
  GitHubProjectsNuiUI.current_project = nil
end

-- Helper for safe string conversion
local function safe_str(value)
  if value == nil or value == vim.NIL then
    return ""
  end
  if type(value) == "string" then
    return value
  end
  return tostring(value)
end

-- Setup highlights
local function setup_highlights()
  vim.api.nvim_set_hl(0, "GitHubProjectsBorder", { fg = "#61AFEF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsTitle", { fg = "#98C379", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsSelected", { fg = "#C678DD", bg = "#3E4452", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsInfo", { fg = "#ABB2BF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsURL", { fg = "#56B6C2", bg = "NONE", underline = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsLabel", { fg = "#E5C07B", bg = "#3E4452" })
  vim.api.nvim_set_hl(0, "GitHubProjectsOpen", { fg = "#98C379", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsClosed", { fg = "#E06C75", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsHeader", { fg = "#61AFEF", bg = "#282C34", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanHeader", { fg = "#61AFEF", bg = "#282C34", bold = true, underline = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanItem", { fg = "#ABB2BF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanSelected", { fg = "#C678DD", bg = "#3E4452", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanBorder", { fg = "#61AFEF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanOpenHeader", { fg = "#98C379", bg = "#282C34", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanClosedHeader", { fg = "#E06C75", bg = "#282C34", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanOpenItem", { fg = "#98C379", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanClosedItem", { fg = "#E06C75", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanInProgressItem", { fg = "#E5C07B", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanDoneItem", { fg = "#56B6C2", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanTodoItem", { fg = "#ABB2BF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanBacklogItem", { fg = "#ABB2BF", bg = "NONE" })
end
setup_highlights()

-- Get devicon if available
local function get_devicon(filename)
  local devicons_ok, devicons = pcall(require, 'nvim-web-devicons')
  if devicons_ok then
    local icon, hl = devicons.get_icon(filename)
    return icon or " "
  end
  return " "
end

-- Show projects using nui.menu
function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("No projects found", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  local items = {}
  for _, project in ipairs(projects) do
    local title = safe_str(project.title)
    local number = safe_str(project.number)
    local short_desc = safe_str(project.shortDescription)
    local updated_at = safe_str(project.updatedAt)

    local icon = get_devicon("project.md")
    local display_text = string.format("%s %s (#%s) - %s (Updated: %s)",
      icon, title, number, short_desc or "No description", updated_at and updated_at:sub(1, 10) or "N/A")

    table.insert(items, menu.item(display_text, { value = project }))
  end

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_menu = menu({
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Select a Project",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  }, {
    lines = items,
    max_width = ui_config.width,
    max_height = ui_config.height,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>", "q" },
      submit = { "<CR>", "<Space>" },
    },
    on_close = function()
      GitHubProjectsNuiUI.current_menu = nil
    end,
    on_submit = function(item)
      GitHubProjectsNuiUI.close_current_popup()
      if item and item.value then
        local project = item.value
        vim.notify("Loading project: " .. project.title, vim.log.levels.INFO)
        
        api.get_project_details(project.number, function(project_data)
          if project_data then
            GitHubProjectsNuiUI.current_project = project_data.project
            M.show_issues_kanban(project_data.statuses, project_data.issues_by_status, project.title)
          else
            vim.notify("Error loading project details", vim.log.levels.ERROR)
          end
        end)
      end
    end,
  })

  GitHubProjectsNuiUI.current_menu:mount()
end

-- Show issues in a visual Kanban board
function M.show_issues_kanban(statuses, issues_by_status, project_title)
  if not statuses or #statuses == 0 then
    vim.notify("No statuses found for this project", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()
  
  GitHubProjectsNuiUI.columns = statuses
  GitHubProjectsNuiUI.issues_by_column = {}
  
  for i, status in ipairs(statuses) do
    local status_name = status.name
    GitHubProjectsNuiUI.issues_by_column[i] = issues_by_status[status_name] or {}
  end

  local ui_config = config.get_ui_config()
  local popup_width = ui_config.width
  local popup_height = ui_config.height

  GitHubProjectsNuiUI.current_popup = popup({
    position = "50%",
    size = {
      width = popup_width,
      height = popup_height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Issues for: " .. project_title,
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = false,
    },
    buf_options = {
      modifiable = true,
    },
    enter = true,
  })

  GitHubProjectsNuiUI.current_popup:mount()
  
  M.render_kanban_view()
  
  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', true)
  
  vim.api.nvim_set_current_win(GitHubProjectsNuiUI.current_popup.winid)

  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', 
    ":lua require('github-projects.ui_nui')._move_selection('down')<CR>", 
    { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', 
    ":lua require('github-projects.ui_nui')._move_selection('up')<CR>", 
    { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'h', 
    ":lua require('github-projects.ui_nui')._move_selection('left')<CR>", 
    { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'l', 
    ":lua require('github-projects.ui_nui')._move_selection('right')<CR>", 
    { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', 
    ":lua require('github-projects.ui_nui')._select_current_issue()<CR>", 
    { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', 
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>", 
    { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', 
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>", 
    { noremap = true, silent = true })
end

-- Get status icon and color
local function get_status_style(status_name)
  local name = status_name:lower()
  
  if name == "open" or name == "todo" or name == "backlog" or name:match("to%s*do") then
    return "📋", "GitHubProjectsKanbanTodoItem"
  elseif name == "in progress" or name:match("progress") or name:match("doing") then
    return "🔄", "GitHubProjectsKanbanInProgressItem"
  elseif name == "done" or name == "complete" or name:match("done") or name:match("complete") then
    return "✅", "GitHubProjectsKanbanDoneItem"
  elseif name == "closed" then
    return "🔴", "GitHubProjectsKanbanClosedItem"
  elseif name:match("review") or name:match("testing") then
    return "👀", "GitHubProjectsKanbanInProgressItem"
  elseif name:match("block") then
    return "🚫", "GitHubProjectsKanbanClosedItem"
  else
    return "📌", "GitHubProjectsKanbanItem"
  end
end

-- Render the Kanban board
function M.render_kanban_view()
  if not GitHubProjectsNuiUI.current_popup then
    return
  end

  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  local popup_width = GitHubProjectsNuiUI.current_popup.win_config.width
  local popup_height = GitHubProjectsNuiUI.current_popup.win_config.height
  
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  
  local columns = GitHubProjectsNuiUI.columns
  local issues_by_column = GitHubProjectsNuiUI.issues_by_column
  
  local num_columns = #columns
  local column_width = math.floor((popup_width - (num_columns + 1)) / num_columns)
  
  -- Draw header
  local header_line = "╭"
  for i = 1, num_columns do
    header_line = header_line .. string.rep("─", column_width)
    if i < num_columns then
      header_line = header_line .. "┬"
    end
  end
  header_line = header_line .. "╮"
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {header_line})
  
  -- Draw column titles
  local title_line = "│"
  for i, column in ipairs(columns) do
    local icon, _ = get_status_style(column.name)
    local title = icon .. " " .. column.name:upper()
    local padding = math.floor((column_width - vim.fn.strwidth(title)) / 2)
    title_line = title_line .. string.rep(" ", padding) .. title .. 
                string.rep(" ", column_width - padding - vim.fn.strwidth(title)) .. "│"
  end
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {title_line})
  
  -- Draw separator below titles
  local separator_line = "├"
  for i = 1, num_columns do
    separator_line = separator_line .. string.rep("─", column_width)
    if i < num_columns then
      separator_line = separator_line .. "┼"
    end
  end
  separator_line = separator_line .. "┤"
  vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, {separator_line})
  
  -- Find max issues to display
  local max_issues = 0
  for i = 1, num_columns do
    local column_issues = issues_by_column[i] or {}
    max_issues = math.max(max_issues, #column_issues)
  end
  
  -- Calculate content height
  local content_height = popup_height - 5 -- Header (3) + Footer (2)
  local visible_issues = math.min(max_issues, content_height)
  
  -- Reset issue map
  GitHubProjectsNuiUI.issue_map = {}
  
  -- Draw content rows
  for i = 1, visible_issues do
    local content_line = "│"
    
    for col_idx = 1, num_columns do
      local column_issues = issues_by_column[col_idx] or {}
      local issue_text = ""
      
      if i <= #column_issues then
        local issue = column_issues[i]
        local number = safe_str(issue.number)
        local title = safe_str(issue.title)
        
        if vim.fn.strwidth(title) > column_width - 6 then
          title = vim.fn.strcharpart(title, 0, column_width - 9) .. "..."
        end
        
        issue_text = "#" .. number .. ": " .. title
        
        GitHubProjectsNuiUI.issue_map[col_idx .. "_" .. i] = issue
      end
      
      local padding = column_width - vim.fn.strwidth(issue_text)
      if padding > 0 then
        issue_text = issue_text .. string.rep(" ", padding)
      end
      content_line = content_line .. issue_text .. "│"
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 2 + i, 3 + i, false, {content_line})
  end
  
  -- Fill remaining rows
  for i = visible_issues + 1, content_height do
    local empty_line = "│"
    for j = 1, num_columns do
      empty_line = empty_line .. string.rep(" ", column_width) .. "│"
    end
    vim.api.nvim_buf_set_lines(bufnr, 2 + i, 3 + i, false, {empty_line})
  end
  
  -- Draw footer
  local footer_line = "╰"
  for i = 1, num_columns do
    footer_line = footer_line .. string.rep("─", column_width)
    if i < num_columns then
      footer_line = footer_line .. "┴"
    end
  end
  footer_line = footer_line .. "╯"
  vim.api.nvim_buf_set_lines(bufnr, popup_height - 2, popup_height - 1, false, {footer_line})
  
  -- Add help text
  local help_text = "Navigation: ←/→ (columns) ↑/↓ (issues) | Enter: Select | q/Esc: Exit"
  local help_padding = math.floor((popup_width - vim.fn.strwidth(help_text)) / 2)
  local help_line = string.rep(" ", help_padding) .. help_text
  vim.api.nvim_buf_set_lines(bufnr, popup_height - 1, popup_height, false, {help_line})
  
  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsKanban")
  
  -- Highlight borders and headers
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", popup_height - 2, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsInfo", popup_height - 1, 0, -1)
  
  -- Highlight column titles
  local col_start = 1
  for i, column in ipairs(columns) do
    local _, highlight_group = get_status_style(column.name)
    
    local col_end = col_start + column_width
    if col_end <= #title_line then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, highlight_group, 1, col_start, col_end)
    end
    col_start = col_end + 1
  end
  
  -- Highlight issues
  for i = 1, visible_issues do
    local line_idx = 2 + i
    local col_start = 0
    
    for col_idx = 1, num_columns do
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", line_idx, col_start, col_start + 1)
      col_start = col_start + 1
      
      local column_issues = issues_by_column[col_idx] or {}
      if i <= #column_issues then
        local issue = column_issues[i]
        local _, highlight_group = get_status_style(columns[col_idx].name)
        
        local col_end = col_start + column_width
        if col_end <= popup_width then
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, highlight_group, line_idx, col_start, col_end)
        end
      end
      
      col_start = col_start + column_width
    end
    
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", line_idx, col_start, col_start + 1)
  end
  
  -- Highlight empty rows
  for i = visible_issues + 1, content_height do
    local line_idx = 2 + i
    local col_start = 0
    
    for j = 1, num_columns + 1 do
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", line_idx, col_start, col_start + 1)
      col_start = col_start + 1
      
      if j <= num_columns then
        local col_end = col_start + column_width
        if col_end <= popup_width then
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Normal", line_idx, col_start, col_end)
        end
        col_start = col_start + column_width
      end
    end
  end
  
  -- Highlight current selection
  M._highlight_selection()
end

-- Highlight the current selection
function M._highlight_selection()
  if not GitHubProjectsNuiUI.current_popup then
    return
  end
  
  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  local popup_width = GitHubProjectsNuiUI.current_popup.win_config.width
  local num_columns = #GitHubProjectsNuiUI.columns
  local column_width = math.floor((popup_width - (num_columns + 1)) / num_columns)
  
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsKanbanSelection")
  
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  local line_idx = 2 + GitHubProjectsNuiUI.current_selection
  local col_idx = GitHubProjectsNuiUI.current_column
  local col_start = 1 + (col_idx - 1) * (column_width + 1)
  local col_end = col_start + column_width
  
  if line_idx < vim.api.nvim_buf_line_count(bufnr) and col_end <= popup_width then
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanSelected", line_idx, col_start, col_end)
  end
end

-- Move selection
function M._move_selection(direction)
  if not GitHubProjectsNuiUI.current_popup then
    return
  end
  
  local columns = GitHubProjectsNuiUI.columns
  local issues_by_column = GitHubProjectsNuiUI.issues_by_column
  local current_column_issues = issues_by_column[GitHubProjectsNuiUI.current_column] or {}
  
  if direction == "up" then
    GitHubProjectsNuiUI.current_selection = math.max(1, GitHubProjectsNuiUI.current_selection - 1)
  elseif direction == "down" then
    local max_issues = #current_column_issues
    GitHubProjectsNuiUI.current_selection = math.min(max_issues, GitHubProjectsNuiUI.current_selection + 1)
    if GitHubProjectsNuiUI.current_selection == 0 then
      GitHubProjectsNuiUI.current_selection = 1
    end
  elseif direction == "left" then
    if GitHubProjectsNuiUI.current_column > 1 then
      GitHubProjectsNuiUI.current_column = GitHubProjectsNuiUI.current_column - 1
      local new_column_issues = issues_by_column[GitHubProjectsNuiUI.current_column] or {}
      GitHubProjectsNuiUI.current_selection = math.min(GitHubProjectsNuiUI.current_selection, #new_column_issues)
      if GitHubProjectsNuiUI.current_selection == 0 then
        GitHubProjectsNuiUI.current_selection = 1
      end
    end
  elseif direction == "right" then
    if GitHubProjectsNuiUI.current_column < #columns then
      GitHubProjectsNuiUI.current_column = GitHubProjectsNuiUI.current_column + 1
      local new_column_issues = issues_by_column[GitHubProjectsNuiUI.current_column] or {}
      GitHubProjectsNuiUI.current_selection = math.min(GitHubProjectsNuiUI.current_selection, #new_column_issues)
      if GitHubProjectsNuiUI.current_selection == 0 then
        GitHubProjectsNuiUI.current_selection = 1
      end
    end
  end
  
  M._highlight_selection()
end

-- Select current issue
function M._select_current_issue()
  if not GitHubProjectsNuiUI.current_popup then
    return
  end
  
  local issue_key = GitHubProjectsNuiUI.current_column .. "_" .. GitHubProjectsNuiUI.current_selection
  local selected_issue = GitHubProjectsNuiUI.issue_map[issue_key]
  
  if selected_issue then
    -- Store current project state before showing issue details
    GitHubProjectsNuiUI.previous_view = {
      project = GitHubProjectsNuiUI.current_project,
      columns = GitHubProjectsNuiUI.columns,
      issues_by_column = GitHubProjectsNuiUI.issues_by_column,
      current_column = GitHubProjectsNuiUI.current_column,
      current_selection = GitHubProjectsNuiUI.current_selection
    }
    
    M.show_issue_details(selected_issue)
  else
    vim.notify("No issue at this position", vim.log.levels.WARN)
  end
end

-- Return to kanban board from issue details
function M._return_to_kanban()
  if GitHubProjectsNuiUI.previous_view then
    local prev = GitHubProjectsNuiUI.previous_view
    GitHubProjectsNuiUI.close_current_popup()
    
    -- Restore project state
    GitHubProjectsNuiUI.current_project = prev.project
    
    -- Show the kanban board again
    M.show_issues_kanban(prev.columns, prev.issues_by_column, prev.project.title)
    
    -- Restore selection
    GitHubProjectsNuiUI.current_column = prev.current_column
    GitHubProjectsNuiUI.current_selection = prev.current_selection
    M._highlight_selection()
  else
    vim.notify("No previous view to return to", vim.log.levels.WARN)
  end
end

-- Show issue details
function M.show_issue_details(issue)
  GitHubProjectsNuiUI.close_current_popup()

  local lines = {}
  local width = 80

  -- Title and header
  table.insert(lines, "╭" .. string.rep("─", width) .. "╮")
  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  
  local title = safe_str(issue.title)
  local title_line = "│  " .. title
  title_line = title_line .. string.rep(" ", width - vim.fn.strwidth(title_line) - 1) .. "│"
  table.insert(lines, title_line)
  
  local number = "#" .. safe_str(issue.number)
  local state = safe_str(issue.state)
  local status = safe_str(issue.status) or state
  local state_icon, _ = get_status_style(status)
  
  local info_line = "│  " .. number .. " - " .. state_icon .. " " .. status:upper()
  info_line = info_line .. string.rep(" ", width - vim.fn.strwidth(info_line) - 1) .. "│"
  table.insert(lines, info_line)
  
  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  table.insert(lines, "├" .. string.rep("─", width) .. "┤")

  -- Labels
  if issue.labels and #issue.labels > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels) do
      table.insert(labels, safe_str(label.name))
    end
    local labels_line = "│  Labels: " .. table.concat(labels, ", ")
    labels_line = labels_line .. string.rep(" ", width - vim.fn.strwidth(labels_line) - 1) .. "│"
    table.insert(lines, labels_line)
  else
    table.insert(lines, "│  Labels: None" .. string.rep(" ", width - 15) .. "│")
  end

  -- Assignees
  local assignee_line = "│  Assignee: "
  if issue.assignees and type(issue.assignees) == "table" and #issue.assignees > 0 then
    local assignees = {}
    for _, assignee in ipairs(issue.assignees) do
      if type(assignee) == "table" and assignee.login then
        table.insert(assignees, safe_str(assignee.login))
      end
    end
    assignee_line = assignee_line .. table.concat(assignees, ", ")
  else
    assignee_line = assignee_line .. "None"
  end
  assignee_line = assignee_line .. string.rep(" ", width - vim.fn.strwidth(assignee_line) - 1) .. "│"
  table.insert(lines, assignee_line)
  
  -- Repository
  local repo_line = "│  Repository: " .. (issue.repository or "Unknown")
  repo_line = repo_line .. string.rep(" ", width - vim.fn.strwidth(repo_line) - 1) .. "│"
  table.insert(lines, repo_line)

  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  
  -- URL
  local url_line = "│  URL: " .. (safe_str(issue.html_url) or "N/A")
  url_line = url_line .. string.rep(" ", width - vim.fn.strwidth(url_line) - 1) .. "│"
  table.insert(lines, url_line)
  
  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  table.insert(lines, "├" .. string.rep("─", width) .. "┤")
  table.insert(lines, "│  Description:" .. string.rep(" ", width - 15) .. "│")
  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")

  -- Description
  local body_lines = vim.split(safe_str(issue.body) or "No description.", "\n")
  for _, line in ipairs(body_lines) do
    -- Break long lines
    while vim.fn.strwidth(line) > width - 6 do
      local display_line = vim.fn.strcharpart(line, 0, width - 6)
      line = vim.fn.strcharpart(line, vim.fn.strwidth(display_line))
      table.insert(lines, "│  " .. display_line .. string.rep(" ", width - vim.fn.strwidth(display_line) - 4) .. "  │")
    end
    table.insert(lines, "│  " .. line .. string.rep(" ", width - vim.fn.strwidth(line) - 4) .. "  │")
  end

  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  table.insert(lines, "├" .. string.rep("─", width) .. "┤")
  table.insert(lines, "│  Press 'o' to open in browser | 'b' to return to board" .. string.rep(" ", width - 50) .. "│")
  table.insert(lines, "╰" .. string.rep("─", width) .. "╯")

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_popup = popup({
    position = "50%",
    size = {
      width = width + 2,
      height = math.min(ui_config.height, #lines),
    },
    border = "none",
    win_options = {
      winhighlight = "Normal:Normal",
      wrap = false,
      scrolloff = 5,
    },
    buf_options = {
      modifiable = true,
    },
    enter = true,
  })

  GitHubProjectsNuiUI.current_popup:mount()

  vim.api.nvim_set_current_win(GitHubProjectsNuiUI.current_popup.winid)
  
  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'readonly', true)

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsIssueDetails")
  
  -- Borders
  for i = 0, #lines - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", i, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", i, width + 1, width + 2)
  end
  
  -- Title and header
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsTitle", 2, 3, -2)
  
  -- Status
  local _, status_highlight = get_status_style(issue.status or issue.state)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, status_highlight, 3, 3, -2)
  
  -- URL
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsURL", 10, 8, -2)

  -- Keymap to open URL
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'o',
    string.format(":lua vim.ui.open('%s'); require('github-projects.ui_nui').close_current_popup()<CR>", safe_str(issue.html_url)),
    { noremap = true, silent = true })

  -- Keymap to return to board
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'b',
    ":lua require('github-projects.ui_nui')._return_to_kanban()<CR>",
    { noremap = true, silent = true })

  -- Keymap to close
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })

  -- Navigation keymaps
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', 
    "j", 
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', 
    "k", 
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'h', 
    "h", 
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'l', 
    "l", 
    { noremap = true, silent = true })

  -- Page scroll keymaps
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-f>', 
    "<C-f>", 
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-b>', 
    "<C-b>", 
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-d>', 
    "<C-d>", 
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-u>', 
    "<C-u>", 
    { noremap = true, silent = true })
end

-- Create issue form
function M.create_issue_form(callback)
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
            body = issue_body or ""
          })
        end)
      end)
    end)
  end)
end

-- Show repositories
function M.show_repositories(repos)
  if not repos or #repos == 0 then
    vim.notify("No repositories found", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  local items = {}
  for _, repo in ipairs(repos) do
    local repo_name = safe_str(repo.name)
    local description = safe_str(repo.description)
    local language = safe_str(repo.language)
    local stars = safe_str(repo.stargazers_count)
    local private_str = repo.private and "🔒 Private" or "🌐 Public"
    local updated_at = safe_str(repo.updated_at)

    local icon = get_devicon(repo_name .. "." .. language:lower())
    if icon == " " then icon = get_devicon("folder") end

    local display_text = string.format("%s %s (%s) - %s | ⭐ %s | %s | Updated: %s",
      icon, repo_name, language, description, stars, private_str, updated_at and updated_at:sub(1, 10) or "N/A")

    table.insert(items, menu.item(display_text, { value = repo }))
  end

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_menu = menu({
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Select a Repository",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  }, {
    lines = items,
    max_width = ui_config.width,
    max_height = ui_config.height,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>", "q" },
      submit = { "<CR>", "<Space>" },
    },
    on_close = function()
      GitHubProjectsNuiUI.current_menu = nil
    end,
    on_submit = function(item)
      GitHubProjectsNuiUI.close_current_popup()
      if item and item.value and item.value.html_url then
        vim.ui.open(item.value.html_url)
      end
    end,
  })

  GitHubProjectsNuiUI.current_menu:mount()
end

-- Close popup (publicly available)
M.close_current_popup = GitHubProjectsNuiUI.close_current_popup

return M
