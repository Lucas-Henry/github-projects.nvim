local api = require("github-projects.api")
local ui = require("github-projects.ui")
local utils = require("github-projects.utils")
local config = require("github-projects.config")

local M = {}

function M.setup(opts)
  config.setup(opts or {})

  if not config.validate() then
    vim.notify("GitHub Projects: Configuração inválida. Verifique o arquivo de configuração.", vim.log.levels.ERROR)
    return
  end

  M.setup_commands()
  M.setup_keymaps()
end

function M.load_projects()
  local projects = api.get_projects()
  if projects then
    ui.show_projects(projects)
  end
end

function M.load_issues(repo)
  api.get_issues(repo, function(issues)
    if issues then
      ui.show_issues_kanban(issues, repo or "Organization Issues") -- Passa o repo como título ou um padrão
    else
      vim.notify("Erro ao carregar issues", vim.log.levels.ERROR)
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

function M.load_repositories()
  local repos = api.get_repositories()
  if repos then
    ui.show_repositories(repos)
  end
end

return M
