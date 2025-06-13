local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

local ui_module_name = "github-projects.ui"
local nui_loaded_successfully = false

-- Try to load nui.nvim and fallback to native UI
local ok, nui_test_module = pcall(require, 'nui.popup')
if ok then
  local ui_nui_ok, ui_nui_module = pcall(require, 'github-projects.ui_nui')
  if ui_nui_ok then
    ui_module_name = "github-projects.ui_nui"
    nui_loaded_successfully = true
  end
end

local ui = require(ui_module_name)

function M.setup(opts)
  config.setup(opts or {})

  if not config.validate() then
    vim.notify("GitHub Projects: Invalid configuration. Check config file.", vim.log.levels.ERROR)
    return
  end

  M.setup_commands()
  M.setup_keymaps()
end

function M.load_projects()
  api.get_projects(function(projects)
    if projects then
      ui.show_projects(projects)
    else
      vim.notify("Error loading projects", vim.log.levels.ERROR)
    end
  end)
end

function M.load_issues(repo)
  api.get_issues(repo, function(issues)
    if issues then
      ui.show_issues_kanban(issues, repo or "Organization Issues")
    else
      vim.notify("Error loading issues", vim.log.levels.ERROR)
    end
  end)
end

function M.load_repositories()
  api.get_repositories(function(repos)
    if repos then
      ui.show_repositories(repos)
    else
      vim.notify("Error loading repositories", vim.log.levels.ERROR)
    end
  end)
end

function M.create_issue()
  ui.create_issue_form(function(issue_data)
    api.create_issue(issue_data, function(success)
      if success then
        vim.notify("Issue created successfully!", vim.log.levels.INFO)
      else
        vim.notify("Error creating issue", vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.show_projects(args)
  M.load_projects()
end

function M.show_issues(args)
  M.load_issues(args)
end

function M.test_connection()
  api.test_connection(function(success, message)
    if success then
      vim.notify("✅ " .. message, vim.log.levels.INFO)
    else
      vim.notify("❌ Connection error: " .. message, vim.log.levels.ERROR)
    end
  end)
end

function M.setup_commands()
  vim.api.nvim_create_user_command('GitHubProjects', function()
    M.load_projects()
  end, { desc = 'Show GitHub Projects' })

  vim.api.nvim_create_user_command('GitHubIssues', function(opts)
    M.load_issues(opts.args)
  end, { nargs = '?', desc = 'Show GitHub Issues' })

  vim.api.nvim_create_user_command('GitHubCreateIssue', function()
    M.create_issue()
  end, { desc = 'Create GitHub Issue' })

  vim.api.nvim_create_user_command('GitHubRepos', function()
    M.load_repositories()
  end, { desc = 'Show GitHub Repositories' })

  vim.api.nvim_create_user_command('GitHubTest', function()
    M.test_connection()
  end, { desc = 'Test GitHub Connection' })
end

function M.setup_keymaps()
  local keymaps = config.config.keymaps
  local opts = { noremap = true, silent = true }

  if keymaps.projects then
    vim.keymap.set('n', keymaps.projects, ':GitHubProjects<CR>', opts)
  end

  if keymaps.issues then
    vim.keymap.set('n', keymaps.issues, ':GitHubIssues<CR>', opts)
  end

  if keymaps.create_issue then
    vim.keymap.set('n', keymaps.create_issue, ':GitHubCreateIssue<CR>', opts)
  end
end

return M
