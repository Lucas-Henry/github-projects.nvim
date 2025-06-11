local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Criar janela flutuante
local function create_float_window(title, lines)
  local ui_config = config.get_ui_config()
  local width = ui_config.width
  local height = math.min(ui_config.height, #lines + 4)

  -- Calcular posição central
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Criar buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')

  -- Criar janela
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = ui_config.border,
    title = title,
    title_pos = 'center'
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Mapear tecla ESC para fechar
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  return buf, win
end

-- Mostrar projetos
function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("Nenhum projeto encontrado", vim.log.levels.WARN)
    return
  end

  local lines = {
    "=== PROJETOS GITHUB ===",
    ""
  }

  for i, project in ipairs(projects) do
    table.insert(lines, string.format("%d. %s", i, project.title or "Sem título"))
    if project.description and project.description ~= "" then
      table.insert(lines, "   " .. project.description)
    end
    table.insert(lines, "   URL: " .. (project.url or "N/A"))
    table.insert(lines, "")
  end

  table.insert(lines, "Pressione ESC para fechar")

  create_float_window("GitHub Projects", lines)
end

-- Mostrar issues
function M.show_issues(issues)
  if not issues or #issues == 0 then
    vim.notify("Nenhuma issue encontrada", vim.log.levels.WARN)
    return
  end

  local lines = {
    "=== ISSUES GITHUB ===",
    ""
  }

  for i, issue in ipairs(issues) do
    local state_icon = issue.state == "open" and "🟢" or "🔴"
    table.insert(lines, string.format("%s #%d: %s", state_icon, issue.number, issue.title))

    if issue.labels and #issue.labels > 0 then
      local labels = {}
      for _, label in ipairs(issue.labels) do
        table.insert(labels, label.name)
      end
      table.insert(lines, "   Labels: " .. table.concat(labels, ", "))
    end

    if issue.assignee then
      table.insert(lines, "   Assignee: " .. issue.assignee.login)
    end

    table.insert(lines, "   URL: " .. issue.html_url)
    table.insert(lines, "")
  end

  table.insert(lines, "Pressione ESC para fechar")

  create_float_window("GitHub Issues", lines)
end

-- Formulário para criar issue
function M.create_issue_form(callback)
  -- Primeiro, obter lista de repositórios
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("Nenhum repositório encontrado", vim.log.levels.ERROR)
      return
    end

    -- Criar lista de opções
    local repo_names = {}
    for _, repo in ipairs(repos) do
      table.insert(repo_names, repo.name)
    end

    -- Seletor de repositório
    vim.ui.select(repo_names, {
      prompt = "Selecione o repositório:",
    }, function(selected_repo)
      if not selected_repo then
        return
      end

      -- Input para título
      vim.ui.input({
        prompt = "Título da issue: ",
      }, function(title)
        if not title or title == "" then
          vim.notify("Título é obrigatório", vim.log.levels.ERROR)
          return
        end

        -- Input para corpo (opcional)
        vim.ui.input({
          prompt = "Descrição (opcional): ",
        }, function(body)
          -- Chamar callback com dados da issue
          callback({
            repo = selected_repo,
            title = title,
            body = body or ""
          })
        end)
      end)
    end)
  end)
end

-- Mostrar repositórios
function M.show_repositories(repos)
  if not repos or #repos == 0 then
    vim.notify("Nenhum repositório encontrado", vim.log.levels.WARN)
    return
  end

  local lines = {
    "=== REPOSITÓRIOS GITHUB ===",
    ""
  }

  for i, repo in ipairs(repos) do
    table.insert(lines, string.format("%d. %s", i, repo.name))
    if repo.description and repo.description ~= "" then
      table.insert(lines, "   " .. repo.description)
    end
    table.insert(lines, "   Language: " .. (repo.language or "N/A"))
    table.insert(lines, "   Stars: " .. (repo.stargazers_count or 0))
    table.insert(lines, "   URL: " .. repo.html_url)
    table.insert(lines, "")
  end

  table.insert(lines, "Pressione ESC para fechar")

  create_float_window("GitHub Repositories", lines)
end

return M
