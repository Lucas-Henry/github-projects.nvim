local api = require("github-projects.api")
local ui = require("github-projects.ui")
local utils = require("github-projects.utils")

local M = {}

M.config = {
  github_token = "",
  github_username = "",
  project_owner = "",
  project_number = 1,
  column_names = {
    "Backlog",
    "Todo",
    "In Progress",
    "Done",
  },
  -- You can add more configuration options here
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  api.setup(M.config)
  ui.setup(M.config)
end

function M.load_projects()
  local projects = api.get_projects()
  if projects then
    ui.show_projects(projects)
  end
end

function M.load_issues(repo)
  local issues = api.get_issues(repo)
  if issues then
    ui.show_issues_kanban(issues, repo)
  end
end

function M.create_issue()
  ui.create_issue_form(function(issue_data)
    api.create_issue(issue_data)
  end)
end

function M.load_repositories()
  local repos = api.get_repositories()
  if repos then
    ui.show_repositories(repos)
  end
end

return M
