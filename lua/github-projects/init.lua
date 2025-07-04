local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')
local ui = require('github-projects.ui_nui')
local ui_enhanced = require('github-projects.ui_enhanced')
local pull_requests = require('github-projects.pull_requests')
local cache = require('github-projects.cache')

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

  -- Create commands with both old and new names for compatibility
  vim.api.nvim_create_user_command('GitHubProjects', function()
    M.show_projects()
  end, { desc = 'Show GitHub Projects' })

  vim.api.nvim_create_user_command('GitHubProjectsIssues', function()
    M.show_issues()
  end, { desc = 'Show GitHub Issues' })

  -- Compatibility aliases
  vim.api.nvim_create_user_command('GitHubIssues', function()
    M.show_issues()
  end, { desc = 'Show GitHub Issues' })

  vim.api.nvim_create_user_command('GitHubProjectsRepos', function()
    M.show_repositories()
  end, { desc = 'Show GitHub Repositories' })

  vim.api.nvim_create_user_command('GitHubRepos', function()
    M.show_repositories()
  end, { desc = 'Show GitHub Repositories' })

  vim.api.nvim_create_user_command('GitHubProjectsCreateIssue', function()
    M.create_issue_enhanced()
  end, { desc = 'Create GitHub Issue with Project Board support' })

  vim.api.nvim_create_user_command('GitHubCreateIssue', function()
    M.create_issue_enhanced()
  end, { desc = 'Create GitHub Issue with Project Board support' })

  vim.api.nvim_create_user_command('GitHubProjectsPRs', function()
    M.show_pull_requests()
  end, { desc = 'Show GitHub Pull Requests' })

  vim.api.nvim_create_user_command('GitHubPRs', function()
    M.show_pull_requests()
  end, { desc = 'Show GitHub Pull Requests' })

  vim.api.nvim_create_user_command('GitHubProjectsCreatePR', function()
    M.create_pull_request()
  end, { desc = 'Create GitHub Pull Request' })

  vim.api.nvim_create_user_command('GitHubCreatePR', function()
    M.create_pull_request()
  end, { desc = 'Create GitHub Pull Request' })

  vim.api.nvim_create_user_command('GitHubProjectsTest', function()
    M.test_connection()
  end, { desc = 'Test GitHub API connection' })

  vim.api.nvim_create_user_command('GitHubProjectsClearCache', function()
    cache.clear()
    vim.notify("Cache cleared!", vim.log.levels.INFO)
  end, { desc = 'Clear GitHub Projects cache' })

  -- Setup keymaps if configured
  local keymaps = config.get_keymaps()
  if keymaps then
    if keymaps.projects then
      vim.keymap.set('n', keymaps.projects, ':GitHubProjects<CR>', { desc = 'GitHub Projects' })
    end
    if keymaps.issues then
      vim.keymap.set('n', keymaps.issues, ':GitHubIssues<CR>', { desc = 'GitHub Issues' })
    end
    if keymaps.create_issue then
      vim.keymap.set('n', keymaps.create_issue, ':GitHubCreateIssue<CR>', { desc = 'Create GitHub Issue' })
    end
    if keymaps.repos then
      vim.keymap.set('n', keymaps.repos, ':GitHubRepos<CR>', { desc = 'GitHub Repositories' })
    end
    if keymaps.pull_requests then
      vim.keymap.set('n', keymaps.pull_requests, ':GitHubPRs<CR>', { desc = 'GitHub Pull Requests' })
    end
    if keymaps.create_pr then
      vim.keymap.set('n', keymaps.create_pr, ':GitHubCreatePR<CR>', { desc = 'Create GitHub Pull Request' })
    end
  end
end

-- FIXED: Improved show_issues function with proper error handling
function M.show_issues(repo)
  -- First check if we have valid configuration
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("GitHub organization or token not configured. Please check your configuration.", vim.log.levels.ERROR)
    return
  end

  -- Check cache first with proper key handling
  local cache_key = repo or "all"
  local cached_issues = cache.get("issues", cache_key)

  if cached_issues and #cached_issues > 0 then
    vim.notify("Using cached issues (" .. #cached_issues .. " found)", vim.log.levels.INFO)
    M._show_issues_kanban(cached_issues, repo)
    return
  end

  -- Show loading notification only
  vim.notify("Loading issues from GitHub... This may take a moment.", vim.log.levels.INFO)

  -- Load issues with proper error handling
  api.get_issues(repo, function(issues)
    -- Handle the response properly
    if not issues then
      vim.notify("Failed to load issues. Please check your GitHub configuration and try again.", vim.log.levels.ERROR)
      return
    end

    if #issues == 0 then
      vim.notify("No issues found in " .. (repo or "organization"), vim.log.levels.WARN)
      -- Show empty state
      M._show_issues_kanban({}, repo)
      return
    end

    -- Success case
    cache.set(issues, "issues", cache_key)
    vim.notify("Successfully loaded " .. #issues .. " issues", vim.log.levels.INFO)
    M._show_issues_kanban(issues, repo)
  end)
end

-- IMPROVED: Better kanban conversion with error handling
function M._show_issues_kanban(issues, repo)
  if not issues then
    vim.notify("No issues data to display", vim.log.levels.ERROR)
    return
  end

  -- Convert to kanban format for backward compatibility
  local issues_by_status = {
    ["Open"] = {},
    ["Closed"] = {}
  }

  for _, issue in ipairs(issues) do
    if issue and issue.state then
      local status = (issue.state == "open" or issue.state == "OPEN") and "Open" or "Closed"
      table.insert(issues_by_status[status], issue)
    end
  end

  local statuses = {
    { name = "Open",   id = "open" },
    { name = "Closed", id = "closed" }
  }

  -- Call UI with proper error handling
  local success, err = pcall(function()
    ui.show_issues_kanban(statuses, issues_by_status, repo or "All Issues")
  end)

  if not success then
    vim.notify("Error displaying issues: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- IMPROVED: Better projects loading
function M.show_projects()
  -- First check configuration
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("GitHub organization or token not configured. Please check your configuration.", vim.log.levels.ERROR)
    return
  end

  -- Check cache first
  local cached_projects = cache.get("projects")

  if cached_projects and #cached_projects > 0 then
    vim.notify("Using cached projects (" .. #cached_projects .. " found)", vim.log.levels.INFO)
    ui.show_projects(cached_projects)
    return
  end

  vim.notify("Loading projects from GitHub...", vim.log.levels.INFO)
  api.get_projects(function(projects)
    if not projects then
      vim.notify("Failed to load projects. Check your GitHub configuration.", vim.log.levels.ERROR)
      return
    end

    if #projects == 0 then
      vim.notify("No projects found in organization " .. org, vim.log.levels.WARN)
      ui.show_projects({})
      return
    end

    cache.set(projects, "projects")
    vim.notify("Successfully loaded " .. #projects .. " projects", vim.log.levels.INFO)
    ui.show_projects(projects)
  end)
end

-- IMPROVED: Better repositories loading
function M.show_repositories()
  -- Check configuration first
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("GitHub organization or token not configured. Please check your configuration.", vim.log.levels.ERROR)
    return
  end

  -- Check cache first
  local cached_repos = cache.get("repositories")

  if cached_repos and #cached_repos > 0 then
    vim.notify("Using cached repositories (" .. #cached_repos .. " found)", vim.log.levels.INFO)
    ui.show_repositories(cached_repos)
    return
  end

  vim.notify("Loading repositories from GitHub...", vim.log.levels.INFO)
  api.get_repositories(function(repos)
    if not repos then
      vim.notify("Failed to load repositories. Check your GitHub configuration.", vim.log.levels.ERROR)
      return
    end

    if #repos == 0 then
      vim.notify("No repositories found in organization " .. org, vim.log.levels.WARN)
      ui.show_repositories({})
      return
    end

    cache.set(repos, "repositories")
    vim.notify("Successfully loaded " .. #repos .. " repositories", vim.log.levels.INFO)
    ui.show_repositories(repos)
  end)
end

-- IMPROVED: Test connection with better feedback
function M.test_connection()
  vim.notify("Testing GitHub connection...", vim.log.levels.INFO)

  local org = config.get_org()
  local token = config.get_token()

  if not org then
    vim.notify("❌ Organization not configured", vim.log.levels.ERROR)
    return
  end

  if not token then
    vim.notify("❌ Access token not configured", vim.log.levels.ERROR)
    return
  end

  api.test_connection(function(success, message)
    if success then
      vim.notify("✅ Connection successful: " .. message, vim.log.levels.INFO)
      vim.notify("Organization: " .. org, vim.log.levels.INFO)
    else
      vim.notify("❌ Connection failed: " .. (message or "Unknown error"), vim.log.levels.ERROR)
      vim.notify("Please check your token and organization configuration", vim.log.levels.ERROR)
    end
  end)
end

-- Keep all your other functions as they were, they look fine
function M.create_issue_enhanced()
  ui_enhanced.create_issue_with_project_selection(function(issue_data)
    if issue_data then
      vim.notify("Creating issue...", vim.log.levels.INFO)
      api.create_issue(issue_data, function(success)
        if success then
          vim.notify("Issue created successfully!", vim.log.levels.INFO)
          -- Clear cache to refresh data
          cache.clear_key("issues")

          -- If issue was created with project context, add it to the project
          if issue_data.project and issue_data.status then
            vim.notify("Issue created and will be added to project board", vim.log.levels.INFO)
          end
        else
          vim.notify("Failed to create issue", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

function M.show_pull_requests()
  -- First check configuration
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("GitHub organization or token not configured. Please check your configuration.", vim.log.levels.ERROR)
    return
  end

  -- Check cache first
  local cached_repos = cache.get("repositories")

  if cached_repos then
    M._show_pr_selection(cached_repos)
    return
  end

  vim.notify("Loading repositories...", vim.log.levels.INFO)
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("No repositories found", vim.log.levels.ERROR)
      return
    end

    -- Cache repositories
    cache.set(repos, "repositories")
    M._show_pr_selection(repos)
  end)
end

function M._show_pr_selection(repos)
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

    -- Check cache for PRs
    local cached_prs = cache.get("prs", selected_repo)

    if cached_prs then
      M._show_pr_list(cached_prs, selected_repo)
      return
    end

    vim.notify("Loading pull requests for " .. selected_repo .. "...", vim.log.levels.INFO)
    api.get_pull_requests(selected_repo, function(prs)
      if not prs or #prs == 0 then
        vim.notify("No pull requests found in " .. selected_repo, vim.log.levels.WARN)
        return
      end

      -- Cache PRs
      cache.set(prs, "prs", selected_repo)
      vim.notify("Loaded " .. #prs .. " pull requests", vim.log.levels.INFO)
      M._show_pr_list(prs, selected_repo)
    end)
  end)
end

function M._show_pr_list(prs, selected_repo)
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
end

function M.create_pull_request()
  -- Check configuration first
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    vim.notify("GitHub organization or token not configured. Please check your configuration.", vim.log.levels.ERROR)
    return
  end

  -- Check cache first
  local cached_repos = cache.get("repositories")

  if cached_repos then
    M._create_pr_with_repos(cached_repos)
    return
  end

  vim.notify("Loading repositories...", vim.log.levels.INFO)
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("No repositories found", vim.log.levels.ERROR)
      return
    end

    cache.set(repos, "repositories")
    M._create_pr_with_repos(repos)
  end)
end

function M._create_pr_with_repos(repos)
  local repo_names = {}
  for _, repo in ipairs(repos) do
    table.insert(repo_names, repo.name)
  end

  vim.ui.select(repo_names, {
    prompt = "Select Repository for PR:",
    format_item = function(item) return item end,
  }, function(selected_repo)
    if not selected_repo then
      return
    end

    vim.ui.input({ prompt = "PR Title: " }, function(pr_title)
      if not pr_title or pr_title == "" then
        vim.notify("Title is required", vim.log.levels.ERROR)
        return
      end

      vim.ui.input({ prompt = "Head Branch (source): " }, function(head_branch)
        if not head_branch or head_branch == "" then
          vim.notify("Head branch is required", vim.log.levels.ERROR)
          return
        end

        vim.ui.input({ prompt = "Base Branch (target, default: main): " }, function(base_branch)
          base_branch = base_branch and base_branch ~= "" and base_branch or "main"

          vim.ui.input({ prompt = "PR Description (optional): " }, function(pr_body)
            vim.notify("Creating pull request...", vim.log.levels.INFO)
            api.create_pull_request({
              repo = selected_repo,
              title = pr_title,
              body = pr_body or "",
              head_branch = head_branch,
              base_branch = base_branch
            }, function(success)
              if success then
                vim.notify("Pull request created successfully!", vim.log.levels.INFO)
                -- Clear PR cache to refresh data
                cache.clear_key("prs", selected_repo)
              else
                vim.notify("Failed to create pull request", vim.log.levels.ERROR)
              end
            end)
          end)
        end)
      end)
    end)
  end)
end

function M.create_issue()
  ui.create_issue_form(function(issue_data)
    if issue_data then
      vim.notify("Creating issue...", vim.log.levels.INFO)
      api.create_issue(issue_data, function(success)
        if success then
          vim.notify("Issue created successfully!", vim.log.levels.INFO)
          cache.clear_key("issues")
        else
          vim.notify("Failed to create issue", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

return M
