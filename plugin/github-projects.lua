-- ~/github-projects/plugin/github-projects.lua

if vim.g.loaded_github_projects then
  return
end
vim.g.loaded_github_projects = true

vim.api.nvim_create_user_command('GitHubProjects', function(opts)
  require('github-projects').show_projects(opts.args)
end, {
  nargs = '?',
  desc = 'Show GitHub Projects'
})

vim.api.nvim_create_user_command('GitHubIssues', function(opts)
  require('github-projects').show_issues(opts.args)
end, {
  nargs = '?',
  desc = 'Show GitHub Issues'
})

vim.api.nvim_create_user_command('GitHubCreateIssue', function()
  require('github-projects').create_issue()
end, {
  desc = 'Create GitHub Issue'
})
