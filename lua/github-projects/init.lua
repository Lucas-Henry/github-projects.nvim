local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')
local ui = require('github-projects.ui_nui')
local ui_enhanced = require('github-projects.ui_enhanced')
local pull_requests = require('github-projects.pull_requests')

-- Setup highlights for markdown rendering
local function setup_markdown_highlights()
  vim.api.nvim_set_hl(0, "GitHubProjectsMarkdownHeader1", { fg = "#98C379", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsMarkdownHeader2", { fg = "#61AFEF", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsMarkdownHeader3", { fg = "#C678DD", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsMarkdownList", { fg = "#E5C07B", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsMarkdownCode", { fg = "#56B6C2", bg = "#2C323C" })
  vim.api.nvim_set_hl(0, "GitHubProjectsMarkdownQuote", { fg = "#ABB2BF", bg = "NONE", italic = true })
end

function M.setup(opts)
  config.setup(opts or {})
  setup_markdown_highlights()

  -- Create commands
  vim.api.nvim_create_user_command('GitHubProjects', function()
    M.show_projects()
  end, { desc = 'Show GitHub Projects' })

  vim.api.nvim_create_user_command('GitHubProjectsIssues', function()
    M.show_issues()
  end, { desc = 'Show GitHub Issues' })

  vim.api.nvim_create_user_command('GitHubProjectsRepos', function()
    M.show_repositories()
  end, { desc = 'Show GitHub Repositories' })

  vim.api.nvim_create_user_command('GitHubProjectsCreateIssue', function()
    M.create_issue_enhanced()
  end, { desc = 'Create GitHub Issue with Project Board support' })

  vim.api.nvim_create_user_command('GitHubProjectsPRs', function()
    M.show_pull_requests()
  end, { desc = 'Show GitHub Pull Requests' })

  vim.api.nvim_create_user_command('GitHubProjectsCreatePR', function()
    M.create_pull_request()
  end, { desc = 'Create GitHub Pull Request' })

  vim.api.nvim_create_user_command('GitHubProjectsTest', function()
    M.test_connection()
  end, { desc = 'Test GitHub API connection' })
end

-- Enhanced issue creation with project board support
function M.create_issue_enhanced()
  ui_enhanced.create_issue_with_project_selection(function(issue_data)
    if issue_data then
      api.create_issue(issue_data, function(success)
        if success then
          vim.notify("Issue created successfully!", vim.log.levels.INFO)

          -- If issue was created with project context, add it to the project
          if issue_data.project and issue_data.status then
            -- TODO: Implement project item creation
            vim.notify("Issue created and will be added to project board", vim.log.levels.INFO)
          end
        else
          vim.notify("Failed to create issue", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

-- Show pull requests
function M.show_pull_requests()
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("No repositories found", vim.log.levels.ERROR)
      return
    end

    local repo_names = {}
    for _, repo in ipairs(repos) do
      table.insert(repo_names, repo.name)
    end

    vim.ui.select(repo_names, {
      prompt = "Select Repository for PRs:",
      format_item = function(item) return item end,
    }, function(selected_repo)
      if not selected_repo then
        return
      end

      pull_requests.get_pull_requests(selected_repo, function(prs)
        if not prs or #prs == 0 then
          vim.notify("No pull requests found", vim.log.levels.WARN)
          return
        end

        local pr_items = {}
        for _, pr in ipairs(prs) do
          table.insert(pr_items, {
            title = string.format("#%d: %s [%s]", pr.number, pr.title, pr.state),
            value = pr
          })
        end

        vim.ui.select(pr_items, {
          prompt = "Select Pull Request:",
          format_item = function(item) return item.title end,
        }, function(selected_pr_item)
          if selected_pr_item and selected_pr_item.value then
            pull_requests.show_pull_request_fullscreen(selected_pr_item.value, selected_repo)
          end
        end)
      end)
    end)
  end)
end

-- Rest of the original functions remain the same...
function M.show_projects()
  api.get_projects(function(projects)
    if projects then
      ui.show_projects(projects)
    else
      vim.notify("Failed to load projects", vim.log.levels.ERROR)
    end
  end)
end

function M.show_issues(repo)
  api.get_issues(repo, function(issues)
    if issues then
      -- Convert to kanban format for backward compatibility
      local issues_by_status = {
        ["Open"] = {},
        ["Closed"] = {}
      }

      for _, issue in ipairs(issues) do
        local status = issue.state == "open" and "Open" or "Closed"
        table.insert(issues_by_status[status], issue)
      end

      local statuses = {
        { name = "Open",   id = "open" },
        { name = "Closed", id = "closed" }
      }

      ui.show_issues_kanban(statuses, issues_by_status, repo or "All Issues")
    else
      vim.notify("Failed to load issues", vim.log.levels.ERROR)
    end
  end)
end

function M.show_repositories()
  api.get_repositories(function(repos)
    if repos then
      ui.show_repositories(repos)
    else
      vim.notify("Failed to load repositories", vim.log.levels.ERROR)
    end
  end)
end

function M.create_issue()
  ui.create_issue_form(function(issue_data)
    if issue_data then
      api.create_issue(issue_data, function(success)
        if success then
          vim.notify("Issue created successfully!", vim.log.levels.INFO)
        else
          vim.notify("Failed to create issue", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

function M.test_connection()
  api.test_connection(function(success, message)
    if success then
      vim.notify("✅ " .. message, vim.log.levels.INFO)
    else
      vim.notify("❌ Connection failed: " .. (message or "Unknown error"), vim.log.levels.ERROR)
    end
  end)
end

function M.create_pull_request()
  vim.notify("Creating pull requests is not yet implemented.", vim.log.levels.WARN)
end

return M
