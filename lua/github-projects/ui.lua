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

-- Função helper para converter valores do Vim para strings seguras
local function safe_tostring(value)
  if value == nil or value == vim.NIL then
    return nil
  end
  if type(value) == "string" then
    return value
  end
  return tostring(value)
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
    local title = safe_tostring(project.title) or "Sem título"
    local number = safe_tostring(project.number) or "N/A"

    table.insert(lines, string.format("%d. %s (#%s)", i, title, number))

    -- Tratamento seguro para shortDescription
    local short_desc = safe_tostring(project.shortDescription)
    if short_desc and short_desc ~= "" then
      table.insert(lines, "   " .. short_desc)
    end

    local url = safe_tostring(project.url) or "N/A"
    table.insert(lines, "   URL: " .. url)

    local id = safe_tostring(project.id) or "N/A"
    table.insert(lines, "   ID: " .. id)

    local updated_at = safe_tostring(project.updatedAt)
    if updated_at then
      table.insert(lines, "   Atualizado: " .. updated_at)
    end

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
    local number = safe_tostring(issue.number) or "N/A"
    local title = safe_tostring(issue.title) or "Sem título"

    table.insert(lines, string.format("%s #%s: %s", state_icon, number, title))

    if issue.labels and #issue.labels > 0 then
      local labels = {}
      for _, label in ipairs(issue.labels) do
        local label_name = safe_tostring(label.name)
        if label_name then
          table.insert(labels, label_name)
        end
      end
      if #labels > 0 then
        table.insert(lines, "   Labels: " .. table.concat(labels, ", "))
      end
    end

    if issue.assignee and issue.assignee.login then
      local assignee = safe_tostring(issue.assignee.login)
      if assignee then
        table.insert(lines, "   Assignee: " .. assignee)
      end
    end

    if issue.user and issue.user.login then
      local author = safe_tostring(issue.user.login)
      if author then
        table.insert(lines, "   Author: " .. author)
      end
    end

    local html_url = safe_tostring(issue.html_url)
    if html_url then
      table.insert(lines, "   URL: " .. html_url)
    end

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
      local repo_name = safe_tostring(repo.name)
      if repo_name then
        table.insert(repo_names, repo_name)
      end
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
    local repo_name = safe_tostring(repo.name) or "Sem nome"
    table.insert(lines, string.format("%d. %s", i, repo_name))

    local description = safe_tostring(repo.description)
    if description and description ~= "" then
      table.insert(lines, "   " .. description)
    end

    local language = safe_tostring(repo.language) or "N/A"
    table.insert(lines, "   Language: " .. language)

    local stars = safe_tostring(repo.stargazers_count) or "0"
    table.insert(lines, "   Stars: " .. stars)

    local private_str = repo.private and "Sim" or "Não"
    table.insert(lines, "   Private: " .. private_str)

    local html_url = safe_tostring(repo.html_url)
    if html_url then
      table.insert(lines, "   URL: " .. html_url)
    end

    local updated_at = safe_tostring(repo.updated_at)
    if updated_at then
      table.insert(lines, "   Atualizado: " .. updated_at)
    end

    table.insert(lines, "")
  end

  table.insert(lines, "")
  table.insert(lines, "Ações:")
  table.insert(lines, "  ESC/q - Fechar")
  table.insert(lines, "  ENTER - Abrir URL (se cursor estiver na linha)")

  create_float_window("GitHub Repositories", lines)
end

return M
