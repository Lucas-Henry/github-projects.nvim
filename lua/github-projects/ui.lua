local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

local function create_float_window(title, lines)
  local ui_config = config.get_ui_config()
  local width = ui_config.width
  local height = math.min(ui_config.height, #lines + 4)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Usar a nova API para definir opções de buffer
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

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

  -- Adicionar syntax highlighting
  vim.api.nvim_set_option_value('filetype', 'github-projects', { buf = buf })

  -- Keymaps para o buffer
  local keymaps = {
    ['<Esc>'] = function() vim.api.nvim_win_close(win, true) end,
    ['q'] = function() vim.api.nvim_win_close(win, true) end,
    ['<CR>'] = function()
      local line = vim.api.nvim_get_current_line()
      local url = line:match('URL: (https://[%S]+)')
      if url then
        vim.ui.open(url)
      end
    end
  }

  for key, func in pairs(keymaps) do
    vim.keymap.set('n', key, func, { buffer = buf, nowait = true, silent = true })
  end

  return buf, win
end

function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("Nenhum projeto encontrado", vim.log.levels.WARN)
    return
  end

  local lines = {
    "=== PROJETOS GITHUB V2 ===",
    ""
  }

  for i, project in ipairs(projects) do
    table.insert(lines, string.format("%d. %s (#%s)", i, project.title or "Sem título", project.number or "N/A"))

    if project.shortDescription and project.shortDescription ~= "" then
      table.insert(lines, "   " .. project.shortDescription)
    end

    table.insert(lines, "   URL: " .. (project.url or "N/A"))
    table.insert(lines, "   ID: " .. (project.id or "N/A"))
    table.insert(lines, "")
  end

  table.insert(lines, "")
  table.insert(lines, "Ações:")
  table.insert(lines, "  ESC/q - Fechar")
  table.insert(lines, "  ENTER - Abrir URL (se cursor estiver na linha)")

  create_float_window("GitHub Projects V2", lines)
end

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

  table.insert(lines, "")
  table.insert(lines, "Ações:")
  table.insert(lines, "  ESC/q - Fechar")
  table.insert(lines, "  ENTER - Abrir URL (se cursor estiver na linha)")

  create_float_window("GitHub Issues", lines)
end

function M.create_issue_form(callback)
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("Nenhum repositório encontrado", vim.log.levels.ERROR)
      return
    end

    local repo_names = {}
    for _, repo in ipairs(repos) do
      table.insert(repo_names, repo.name)
    end

    vim.ui.select(repo_names, {
      prompt = "Selecione o repositório:",
    }, function(selected_repo)
      if not selected_repo then
        return
      end

      vim.ui.input({
        prompt = "Título da issue: ",
      }, function(title)
        if not title or title == "" then
          vim.notify("Título é obrigatório", vim.log.levels.ERROR)
          return
        end

        vim.ui.input({
          prompt = "Descrição (opcional): ",
        }, function(body)
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
    table.insert(lines, "   Private: " .. (repo.private and "Sim" or "Não"))
    table.insert(lines, "   URL: " .. repo.html_url)
    table.insert(lines, "")
  end

  table.insert(lines, "")
  table.insert(lines, "Ações:")
  table.insert(lines, "  ESC/q - Fechar")
  table.insert(lines, "  ENTER - Abrir URL (se cursor estiver na linha)")

  create_float_window("GitHub Repositories", lines)
end

return M
