local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Tenta carregar a UI baseada em nui.nvim, com fallback para a UI nativa
local ui = nil
local nui_available, nui_popup = pcall(require, 'nui.popup') -- Verifica se nui.popup pode ser carregado

if nui_available then
  vim.notify("DEBUG: Usando nui.nvim UI", vim.log.levels.INFO)
  ui = require('github-projects.ui_nui') -- Novo arquivo para a UI com nui.nvim
else
  vim.notify("DEBUG: nui.nvim não disponível, usando UI nativa como fallback", vim.log.levels.INFO)
  ui = require('github-projects.ui') -- Seu arquivo ui.lua atual
end

function M.setup(opts)
  vim.notify("DEBUG: init.lua M.setup started", vim.log.levels.INFO)
  config.setup(opts or {})

  if not config.validate() then
    vim.notify("GitHub Projects: Configuração inválida. Verifique o arquivo de configuração.", vim.log.levels.ERROR)
    return
  end

  -- Chamadas de setup de comandos e keymaps devem vir aqui no final
  M.setup_commands()
  M.setup_keymaps()
  vim.notify("DEBUG: init.lua M.setup finished", vim.log.levels.INFO)
end

function M.load_projects()
  api.get_projects(function(projects)
    if projects then
      ui.show_projects(projects)
    else
      vim.notify("Erro ao carregar projetos", vim.log.levels.ERROR)
    end
  end)
end

function M.load_issues(repo)
  api.get_issues(repo, function(issues)
    if issues then
      ui.show_issues_kanban(issues, repo or "Organization Issues")
    else
      vim.notify("Erro ao carregar issues", vim.log.levels.ERROR)
    end
  end)
end

function M.load_repositories()
  api.get_repositories(function(repos)
    if repos then
      ui.show_repositories(repos)
    else
      vim.notify("Erro ao carregar repositórios", vim.log.levels.ERROR)
    end
  end)
end

function M.create_issue()
  ui.create_issue_form(function(issue_data)
    api.create_issue(issue_data, function(success)
      if success then
        vim.notify("Issue criada com sucesso!", vim.log.levels.INFO)
      else
        vim.notify("Erro ao criar issue", vim.log.levels.ERROR)
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
      vim.notify("❌ Erro de conexão: " .. message, vim.log.levels.ERROR)
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
