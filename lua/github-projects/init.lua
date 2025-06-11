local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')
local ui = require('github-projects.ui')

-- Estado global do plugin
M.state = {
  projects = {},
  issues = {},
  current_project = nil,
  loaded = false
}

-- Inicializar o plugin
function M.setup(opts)
  config.setup(opts or {})

  -- Verificar se as credenciais estão configuradas
  if not config.validate() then
    vim.notify("GitHub Projects: Configure suas credenciais em ~/.config/gh_access.conf", vim.log.levels.ERROR)
    return
  end

  M.state.loaded = true
  vim.notify("GitHub Projects: Plugin carregado com sucesso!", vim.log.levels.INFO)
end

-- Carregar projetos
function M.load_projects()
  if not M.state.loaded then
    vim.notify("GitHub Projects: Plugin não inicializado", vim.log.levels.ERROR)
    return
  end

  api.get_projects(function(projects)
    if projects then
      M.state.projects = projects
      ui.show_projects(projects)
    else
      vim.notify("Erro ao carregar projetos", vim.log.levels.ERROR)
    end
  end)
end

-- Carregar issues
function M.load_issues(repo)
  if not M.state.loaded then
    vim.notify("GitHub Projects: Plugin não inicializado", vim.log.levels.ERROR)
    return
  end

  api.get_issues(repo or "", function(issues)
    if issues then
      M.state.issues = issues
      ui.show_issues(issues)
    else
      vim.notify("Erro ao carregar issues", vim.log.levels.ERROR)
    end
  end)
end

-- Criar nova issue
function M.create_issue()
  if not M.state.loaded then
    vim.notify("GitHub Projects: Plugin não inicializado", vim.log.levels.ERROR)
    return
  end

  ui.create_issue_form(function(issue_data)
    api.create_issue(issue_data, function(success)
      if success then
        vim.notify("Issue criada com sucesso!", vim.log.levels.INFO)
        M.load_issues() -- Recarregar lista
      else
        vim.notify("Erro ao criar issue", vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Comandos do plugin
function M.setup_commands()
  vim.api.nvim_create_user_command('GHProjects', function()
    M.load_projects()
  end, {})

  vim.api.nvim_create_user_command('GHIssues', function(opts)
    M.load_issues(opts.args)
  end, { nargs = '?' })

  vim.api.nvim_create_user_command('GHCreateIssue', function()
    M.create_issue()
  end, {})
end

-- Atalhos de teclado padrão
function M.setup_keymaps()
  local opts = { noremap = true, silent = true }

  vim.keymap.set('n', '<leader>gp', ':GHProjects<CR>', opts)
  vim.keymap.set('n', '<leader>gi', ':GHIssues<CR>', opts)
  vim.keymap.set('n', '<leader>gc', ':GHCreateIssue<CR>', opts)
end

-- Auto-setup ao carregar

return M
