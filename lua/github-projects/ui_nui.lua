local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Import nui.nvim modules
local popup = require('nui.popup')
local menu = require('nui.menu')

vim.notify("DEBUG: ui_nui.lua loaded (visual Kanban mode)", vim.log.levels.INFO)

-- UI manager
local GitHubProjectsNuiUI = {}
GitHubProjectsNuiUI.current_popup = nil
GitHubProjectsNuiUI.current_menu = nil
GitHubProjectsNuiUI.issue_map = {}
GitHubProjectsNuiUI.current_column = 1
GitHubProjectsNuiUI.current_selection = 1
GitHubProjectsNuiUI.columns = {}
GitHubProjectsNuiUI.issues_by_column = {}

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
end

-- Helper for safe string conversion
local function safe_str(value)
  if value == nil or value == vim.NIL then
    return nil
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
    local title = safe_str(project.title) or "Untitled"
    local number = safe_str(project.number) or "N/A"
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
        vim.notify("Loading issues for project: " .. project.title, vim.log.levels.INFO)
        api.get_issues(nil, function(issues)
          if issues then
            M.show_issues_kanban(issues, project.title)
          else
            vim.notify("Error loading issues for project", vim.log.levels.ERROR)
          end
        end)
      end
    end,
  })

  GitHubProjectsNuiUI.current_menu:mount()
end

-- Group issues by status for Kanban view
local function group_issues_by_status(issues)
  -- Default columns if no custom statuses are found
  local columns = {
    { id = "open", name = "🟢 OPEN", icon = "🟢" },
    { id = "closed", name = "🔴 CLOSED", icon = "🔴" }
  }

  local issues_by_column = {}
  issues_by_column["open"] = {}
  issues_by_column["closed"] = {}

  -- First pass: collect all unique statuses
  local status_set = {}
  for _, issue in ipairs(issues) do
    local status = issue.status or (issue.state == "open" and "open" or "closed")
    status_set[status] = true
  end

  -- If we have custom statuses, use them instead
  local custom_statuses = {}
  for status, _ in pairs(status_set) do
    if status ~= "open" and status ~= "closed" then
      table.insert(custom_statuses, status)
    end
  end

  if #custom_statuses > 0 then
    columns = {}
    for _, status in ipairs(custom_statuses) do
      local icon = "📋"
      if status:lower():match("progress") then
        icon = "🔄"
      elseif status:lower():match("done") or status:lower():match("complete") then
        icon = "✅"
      elseif status:lower():match("todo") or status:lower():match("backlog") then
        icon = "📝"
      elseif status:lower():match("review") then
        icon = "👀"
      end

      table.insert(columns, { id = status, name = icon .. " " .. status:upper(), icon = icon })
      issues_by_column[status] = {}
    end
  end

  -- Group issues by status
  for _, issue in ipairs(issues) do
    local status = issue.status or (issue.state == "open" and "open" or "closed")
    if issues_by_column[status] then
      table.insert(issues_by_column[status], issue)
    else
      -- Fallback to open/closed if status doesn't match any column
      local fallback = issue.state == "open" and "open" or "closed"
      if not issues_by_column[fallback] then
        issues_by_column[fallback] = {}
      end
      table.insert(issues_by_column[fallback], issue)
    end
  end

  return columns, issues_by_column
end

-- Show issues in a visual Kanban board
function M.show_issues_kanban(issues, project_title)
  if not issues or #issues == 0 then
    vim.notify("No issues found", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  -- Group issues by status
  local columns, issues_by_column = group_issues_by_status(issues)

  -- Store for later use
  GitHubProjectsNuiUI.columns = columns
  GitHubProjectsNuiUI.issues_by_column = issues_by_column

  local ui_config = config.get_ui_config()
  local popup_width = ui_config.width
  local popup_height = ui_config.height

  -- Create popup
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
  })

  -- Mount popup before adding content
  GitHubProjectsNuiUI.current_popup:mount()

  -- Draw the Kanban board
  M.render_kanban_view()

  -- Setup keymaps for navigation
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'j',
    ":lua require('github-projects.ui_nui')._move_selection('down')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'k',
    ":lua require('github-projects.ui_nui')._move_selection('up')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'h',
    ":lua require('github-projects.ui_nui')._move_selection('left')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'l',
    ":lua require('github-projects.ui_nui')._move_selection('right')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<CR>',
    ":lua require('github-projects.ui_nui')._select_current_issue()<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'q',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<Esc>',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
end

-- Render the Kanban board
function M.render_kanban_view()
  if not GitHubProjectsNuiUI.current_popup then
    return
  end

  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  local popup_width = GitHubProjectsNuiUI.current_popup.win_config.width
  local popup_height = GitHubProjectsNuiUI.current_popup.win_config.height

  -- Clear buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- Get columns and issues
  local columns = GitHubProjectsNuiUI.columns
  local issues_by_column = GitHubProjectsNuiUI.issues_by_column

  -- Calculate column width
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
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { header_line })

  -- Draw column titles
  local title_line = "│"
  for i, column in ipairs(columns) do
    local title = column.name
    local padding = math.floor((column_width - #title) / 2)
    title_line = title_line .. string.rep(" ", padding) .. title ..
        string.rep(" ", column_width - padding - #title) .. "│"
  end
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { title_line })

  -- Draw separator below titles
  local separator_line = "├"
  for i = 1, num_columns do
    separator_line = separator_line .. string.rep("─", column_width)
    if i < num_columns then
      separator_line = separator_line .. "┼"
    end
  end
  separator_line = separator_line .. "┤"
  vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { separator_line })

  -- Find max issues to display
  local max_issues = 0
  for _, column in ipairs(columns) do
    local column_issues = issues_by_column[column.id] or {}
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

    for col_idx, column in ipairs(columns) do
      local column_issues = issues_by_column[column.id] or {}
      local issue_text = ""

      if i <= #column_issues then
        local issue = column_issues[i]
        local number = safe_str(issue.number) or "?"
        local title = safe_str(issue.title) or "Untitled"

        -- Truncate title if needed
        if #title > column_width - 6 then
          title = title:sub(1, column_width - 9) .. "..."
        end

        issue_text = "#" .. number .. ": " .. title

        -- Add to issue map
        GitHubProjectsNuiUI.issue_map[col_idx .. "_" .. i] = issue
      end

      -- Pad with spaces
      issue_text = issue_text .. string.rep(" ", column_width - #issue_text)
      content_line = content_line .. issue_text .. "│"
    end

    vim.api.nvim_buf_set_lines(bufnr, 2 + i, 3 + i, false, { content_line })
  end

  -- Fill remaining rows
  for i = visible_issues + 1, content_height do
    local empty_line = "│"
    for j = 1, num_columns do
      empty_line = empty_line .. string.rep(" ", column_width) .. "│"
    end
    vim.api.nvim_buf_set_lines(bufnr, 2 + i, 3 + i, false, { empty_line })
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
  vim.api.nvim_buf_set_lines(bufnr, popup_height - 2, popup_height - 1, false, { footer_line })

  -- Add help text
  local help_text = "Navigation: ←/→ (columns) ↑/↓ (issues) | Enter: Select | q/Esc: Exit"
  local help_padding = math.floor((popup_width - #help_text) / 2)
  local help_line = string.rep(" ", help_padding) .. help_text
  vim.api.nvim_buf_set_lines(bufnr, popup_height - 1, popup_height, false, { help_line })

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
    local highlight_group = "GitHubProjectsKanbanHeader"
    if column.id == "open" then
      highlight_group = "GitHubProjectsKanbanOpenHeader"
    elseif column.id == "closed" then
      highlight_group = "GitHubProjectsKanbanClosedHeader"
    end

    -- Safe highlight application with bounds checking
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

    for col_idx, column in ipairs(columns) do
      -- Highlight border characters
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", line_idx, col_start, col_start + 1)
      col_start = col_start + 1

      -- Highlight issue content if exists
      local column_issues = issues_by_column[column.id] or {}
      if i <= #column_issues then
        local highlight_group = "GitHubProjectsKanbanItem"
        if column.id == "open" then
          highlight_group = "GitHubProjectsKanbanOpenItem"
        elseif column.id == "closed" then
          highlight_group = "GitHubProjectsKanbanClosedItem"
        elseif column.id:lower():match("progress") then
          highlight_group = "GitHubProjectsKanbanInProgressItem"
        elseif column.id:lower():match("done") or column.id:lower():match("complete") then
          highlight_group = "GitHubProjectsKanbanDoneItem"
        end

        -- Safe highlight application with bounds checking
        local col_end = col_start + column_width
        if col_end <= #title_line then
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, highlight_group, line_idx, col_start, col_end)
        end
      end

      col_start = col_start + column_width
    end

    -- Highlight last border character
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
        -- Safe highlight application with bounds checking
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

  -- Clear previous highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Calculate position
  local line_idx = 2 + GitHubProjectsNuiUI.current_selection
  local col_idx = GitHubProjectsNuiUI.current_column
  local col_start = 1 + (col_idx - 1) * (column_width + 1)
  local col_end = col_start + column_width

  -- Apply highlight safely
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
  local current_column_id = columns[GitHubProjectsNuiUI.current_column].id
  local current_column_issues = issues_by_column[current_column_id] or {}

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
      local new_column_id = columns[GitHubProjectsNuiUI.current_column].id
      local new_column_issues = issues_by_column[new_column_id] or {}
      GitHubProjectsNuiUI.current_selection = math.min(GitHubProjectsNuiUI.current_selection, #new_column_issues)
      if GitHubProjectsNuiUI.current_selection == 0 then
        GitHubProjectsNuiUI.current_selection = 1
      end
    end
  elseif direction == "right" then
    if GitHubProjectsNuiUI.current_column < #columns then
      GitHubProjectsNuiUI.current_column = GitHubProjectsNuiUI.current_column + 1
      local new_column_id = columns[GitHubProjectsNuiUI.current_column].id
      local new_column_issues = issues_by_column[new_column_id] or {}
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
    M.show_issue_details(selected_issue)
  else
    vim.notify("No issue at this position", vim.log.levels.WARN)
  end
end

-- Show issue details
function M.show_issue_details(issue)
  GitHubProjectsNuiUI.close_current_popup()

  local lines = {}
  local width = 62

  -- Title and header
  table.insert(lines, "╭" .. string.rep("─", width) .. "╮")
  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")

  local title = safe_str(issue.title) or "Untitled"
  local title_line = "│  " .. title
  title_line = title_line .. string.rep(" ", width - #title_line - 1) .. "│"
  table.insert(lines, title_line)

  local number = "#" .. (safe_str(issue.number) or "?")
  local state = safe_str(issue.state) or "unknown"
  local status = safe_str(issue.status) or state
  local state_icon = "📋"

  if status:lower() == "open" then
    state_icon = "🟢"
  elseif status:lower() == "closed" then
    state_icon = "🔴"
  elseif status:lower():match("progress") then
    state_icon = "🔄"
  elseif status:lower():match("done") or status:lower():match("complete") then
    state_icon = "✅"
  elseif status:lower():match("todo") or status:lower():match("backlog") then
    state_icon = "📝"
  elseif status:lower():match("review") then
    state_icon = "👀"
  end

  local info_line = "│  " .. number .. " - " .. state_icon .. " " .. status:upper()
  info_line = info_line .. string.rep(" ", width - #info_line - 1) .. "│"
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
    labels_line = labels_line .. string.rep(" ", width - #labels_line - 1) .. "│"
    table.insert(lines, labels_line)
  else
    table.insert(lines, "│  Labels: None" .. string.rep(" ", width - 15) .. "│")
  end

  -- Assignee and Author
  local assignee_line = "│  Assignee: "
  if issue.assignee and issue.assignee.login then
    assignee_line = assignee_line .. safe_str(issue.assignee.login)
  else
    assignee_line = assignee_line .. "None"
  end
  assignee_line = assignee_line .. string.rep(" ", width - #assignee_line - 1) .. "│"
  table.insert(lines, assignee_line)

  local author_line = "│  Author: "
  if issue.user and issue.user.login then
    author_line = author_line .. safe_str(issue.user.login)
  else
    author_line = author_line .. "Unknown"
  end
  author_line = author_line .. string.rep(" ", width - #author_line - 1) .. "│"
  table.insert(lines, author_line)

  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")

  -- URL
  local url_line = "│  URL: " .. (safe_str(issue.html_url) or "N/A")
  url_line = url_line .. string.rep(" ", width - #url_line - 1) .. "│"
  table.insert(lines, url_line)

  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  table.insert(lines, "├" .. string.rep("─", width) .. "┤")
  table.insert(lines, "│  Description:" .. string.rep(" ", width - 15) .. "│")
  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")

  -- Description
  local body_lines = vim.split(safe_str(issue.body) or "No description.", "\n")
  for _, line in ipairs(body_lines) do
    -- Break long lines
    while #line > width - 6 do
      local display_line = line:sub(1, width - 6)
      line = line:sub(width - 5)
      table.insert(lines, "│  " .. display_line .. string.rep(" ", width - #display_line - 4) .. "  │")
    end
    table.insert(lines, "│  " .. line .. string.rep(" ", width - #line - 4) .. "  │")
  end

  table.insert(lines, "│ " .. string.rep(" ", width - 2) .. " │")
  table.insert(lines, "├" .. string.rep("─", width) .. "┤")
  table.insert(lines, "│  Press 'o' to open in browser" .. string.rep(" ", width - 29) .. "│")
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
    },
  })

  GitHubProjectsNuiUI.current_popup:mount()
  GitHubProjectsNuiUI.current_popup:set_lines(lines)

  -- Apply highlights
  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
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
  local status_highlight = "GitHubProjectsKanbanItem"
  if status:lower() == "open" then
    status_highlight = "GitHubProjectsKanbanOpenItem"
  elseif status:lower() == "closed" then
    status_highlight = "GitHubProjectsKanbanClosedItem"
  elseif status:lower():match("progress") then
    status_highlight = "GitHubProjectsKanbanInProgressItem"
  elseif status:lower():match("done") or status:lower():match("complete") then
    status_highlight = "GitHubProjectsKanbanDoneItem"
  end
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, status_highlight, 3, 3, -2)

  -- URL
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsURL", 10, 8, -2)

  -- Keymap to open URL
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'o',
    string.format(":lua vim.ui.open('%s'); require('github-projects.ui_nui').close_current_popup()<CR>",
      safe_str(issue.html_url)),
    { noremap = true, silent = true })

  -- Keymap to close
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'q',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<Esc>',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
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
      if repo_name then
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
    local repo_name = safe_str(repo.name) or "Unnamed"
    local description = safe_str(repo.description) or "No description"
    local language = safe_str(repo.language) or "N/A"
    local stars = safe_str(repo.stargazers_count) or "0"
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
