local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

vim.notify("DEBUG: ui.lua file loaded (using native UI)", vim.log.levels.INFO)

-- Helper para garantir que valores sejam strings seguras
local function safe_tostring(value)
  if value == nil or value == vim.NIL then
    return nil
  end
  if type(value) == "string" then
    return value
  end
  return tostring(value)
end

-- Helper para criar janelas flutuantes básicas
local function create_floating_window(opts)
  local ui_config = config.get_ui_config()
  local width = opts.width or ui_config.width
  local height = opts.height or ui_config.height
  local title = opts.title or "GitHub Projects"

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true) -- Não listado, não temporário
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'github-projects')

  local win_id = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    border = {
      style = ui_config.border, -- 'rounded', 'single', 'double'
      text = {
        top = title,            -- O título é definido aqui!
        top_align = "center",
      },
    },
    style = 'minimal',
    noautocmd = true,
    focusable = true,
    zindex = 100,
  })

  -- Set window options
  vim.api.nvim_win_set_option(win_id, 'winhighlight', 'Normal:Normal,FloatBorder:GitHubProjectsBorder')
  vim.api.nvim_win_set_option(win_id, 'cursorline', true) -- Ativar cursorline para melhor navegação
  vim.api.nvim_win_set_option(win_id, 'number', false)
  vim.api.nvim_win_set_option(win_id, 'relativenumber', false)

  -- Map <Esc> to close
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })

  return win_id, buf
end

-- Gerenciador de UI principal (simplificado)
local GitHubProjectsUI = {}
GitHubProjectsUI.current_win_id = nil
GitHubProjectsUI.current_buf_id = nil
GitHubProjectsUI.current_issues_data = nil -- Para armazenar as issues do Kanban

function GitHubProjectsUI.close_current_popup()
  if GitHubProjectsUI.current_win_id and vim.api.nvim_win_is_valid(GitHubProjectsUI.current_win_id) then
    vim.api.nvim_win_close(GitHubProjectsUI.current_win_id, true)
  end
  if GitHubProjectsUI.current_buf_id and vim.api.nvim_buf_is_valid(GitHubProjectsUI.current_buf_id) then
    vim.api.nvim_buf_delete(GitHubProjectsUI.current_buf_id, { force = true })
  end
  GitHubProjectsUI.current_win_id = nil
  GitHubProjectsUI.current_buf_id = nil
  GitHubProjectsUI.current_issues_data = nil
end

-- Highlight groups para a UI (mantidos)
local function setup_highlights()
  vim.api.nvim_set_hl(0, "GitHubProjectsBorder", { fg = "#61AFEF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsTitle", { fg = "#98C379", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsSelected", { fg = "#C678DD", bg = "#3E4452", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsInfo", { fg = "#ABB2BF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsURL", { fg = "#56B6C2", bg = "NONE", underline = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsLabel", { fg = "#E5C07B", bg = "#3E4452" })
  vim.api.nvim_set_hl(0, "GitHubProjectsOpen", { fg = "#98C379", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsClosed", { fg = "#E06C75", bg = "NONE", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsHeader", { fg = "#61AFEF", bg = "#282C34", bold = true })
end
setup_highlights()

-- Função para exibir projetos (usando vim.ui.select)
function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("Nenhum projeto encontrado", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, project in ipairs(projects) do
    local title = safe_tostring(project.title) or "Sem título"
    local number = safe_tostring(project.number) or "N/A"
    local short_desc = safe_tostring(project.shortDescription)
    local updated_at = safe_tostring(project.updatedAt)

    local display_text = string.format("%s (#%s) - %s", title, number, short_desc or "Sem descrição")
    if updated_at then
      display_text = display_text .. " (Atualizado: " .. updated_at:sub(1, 10) .. ")"
    end
    table.insert(items, display_text)
  end

  vim.ui.select(items, {
    prompt = "Selecione um Projeto:",
    format_item = function(item) return item end, -- Use o item como está
  }, function(selected_item, idx)
    if selected_item then
      local project = projects[idx]
      vim.notify("Carregando issues para o projeto: " .. project.title, vim.log.levels.INFO)
      api.get_issues(nil, function(issues)
        if issues then
          M.show_issues_kanban(issues, project.title)
        else
          vim.notify("Erro ao carregar issues para o projeto.", vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

-- Função para exibir issues em um formato Kanban-like (Open/Closed) em uma única janela
function M.show_issues_kanban(issues, project_title)
  if not issues or #issues == 0 then
    vim.notify("Nenhuma issue encontrada", vim.log.levels.WARN)
    return
  end

  GitHubProjectsUI.close_current_popup() -- Fecha qualquer UI anterior

  local open_issues = {}
  local closed_issues = {}

  for _, issue in ipairs(issues) do
    if issue.state == "open" then
      table.insert(open_issues, issue)
    else
      table.insert(closed_issues, issue)
    end
  end

  local function format_issue_line(issue)
    local state_icon = issue.state == "open" and "🟢" or "🔴"
    local number = safe_tostring(issue.number) or "N/A"
    local title = safe_tostring(issue.title) or "Sem título"
    local labels_str = ""
    if issue.labels and #issue.labels > 0 then
      local labels = {}
      for _, label in ipairs(issue.labels) do
        table.insert(labels, safe_tostring(label.name))
      end
      labels_str = " [" .. table.concat(labels, ", ") .. "]"
    end
    return string.format("%s #%s: %s%s", state_icon, number, title, labels_str)
  end

  local ui_config = config.get_ui_config()
  local popup_height = ui_config.height
  local popup_width = ui_config.width

  local lines = {}
  local issue_map = {} -- Mapeia o índice da linha para a issue real
  local current_line_idx = 0

  -- Adiciona cabeçalho de Open Issues
  table.insert(lines, "=== 🟢 OPEN ISSUES ===")
  current_line_idx = current_line_idx + 1
  if #open_issues > 0 then
    for _, issue in ipairs(open_issues) do
      table.insert(lines, format_issue_line(issue))
      current_line_idx = current_line_idx + 1
      issue_map[current_line_idx] = issue
    end
  else
    table.insert(lines, "  (Nenhuma issue aberta)")
    current_line_idx = current_line_idx + 1
  end
  table.insert(lines, "") -- Linha em branco para separação
  current_line_idx = current_line_idx + 1

  -- Adiciona cabeçalho de Closed Issues
  table.insert(lines, "=== 🔴 CLOSED ISSUES ===")
  current_line_idx = current_line_idx + 1
  if #closed_issues > 0 then
    for _, issue in ipairs(closed_issues) do
      table.insert(lines, format_issue_line(issue))
      current_line_idx = current_line_idx + 1
      issue_map[current_line_idx] = issue
    end
  else
    table.insert(lines, "  (Nenhuma issue fechada)")
    current_line_idx = current_line_idx + 1
  end

  local win_id, buf_id = create_floating_window({
    title = "Issues para: " .. project_title,
    width = popup_width,
    height = math.min(popup_height, #lines + 4), -- Ajusta altura se houver poucas linhas
  })
  GitHubProjectsUI.current_win_id = win_id
  GitHubProjectsUI.current_buf_id = buf_id
  GitHubProjectsUI.current_issues_data = issue_map -- Armazena o mapa de issues

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Keymap para selecionar issue
  vim.api.nvim_buf_set_keymap(buf_id, 'n', '<CR>',
    ":lua require('github-projects.ui')._handle_issue_selection_from_kanban()<CR>",
    { noremap = true, silent = true })

  -- Foca na janela
  vim.api.nvim_set_current_win(win_id)
end

-- Função auxiliar para lidar com a seleção de issues no Kanban
function M._handle_issue_selection_from_kanban()
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)

  if current_buf ~= GitHubProjectsUI.current_buf_id then
    vim.notify("Erro: Buffer de Kanban não corresponde.", vim.log.levels.ERROR)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(current_win)[1] -- Linha base 1
  local selected_issue = GitHubProjectsUI.current_issues_data[cursor_line]

  if selected_issue then
    M.show_issue_details(selected_issue)
  else
    vim.notify("Nenhuma issue selecionada nesta linha.", vim.log.levels.WARN)
  end
end

-- Função para exibir detalhes de uma issue (usando janela flutuante simples)
function M.show_issue_details(issue)
  GitHubProjectsUI.close_current_popup() -- Fecha qualquer UI anterior

  local lines = {
    "=== DETALHES DA ISSUE ===",
    "",
    string.format("Título: %s", safe_tostring(issue.title) or "N/A"),
    string.format("Número: #%s", safe_tostring(issue.number) or "N/A"),
    string.format("Estado: %s", safe_tostring(issue.state) or "N/A"),
  }

  if issue.labels and #issue.labels > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels) do
      table.insert(labels, safe_tostring(label.name))
    end
    table.insert(lines, "Labels: " .. table.concat(labels, ", "))
  end

  if issue.assignee and issue.assignee.login then
    table.insert(lines, "Assignee: " .. safe_tostring(issue.assignee.login))
  end

  if issue.user and issue.user.login then
    table.insert(lines, "Autor: " .. safe_tostring(issue.user.login))
  end

  table.insert(lines, "")
  table.insert(lines, "URL: " .. safe_tostring(issue.html_url) or "N/A")
  table.insert(lines, "")
  table.insert(lines, "Descrição:")
  table.insert(lines, "")

  local body_lines = vim.split(safe_tostring(issue.body) or "Sem descrição.", "\n")
  for _, line in ipairs(body_lines) do
    table.insert(lines, line)
  end

  -- Adiciona instrução para abrir URL
  table.insert(lines, "")
  table.insert(lines, "Pressione 'o' para abrir no navegador.")

  local win_id, buf_id = create_floating_window({
    title = "Issue #" .. safe_tostring(issue.number),
    height = math.min(config.get_ui_config().height, #lines + 4),
    width = config.get_ui_config().width,
  })
  GitHubProjectsUI.current_win_id = win_id
  GitHubProjectsUI.current_buf_id = buf_id

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Keymap para abrir URL
  vim.api.nvim_buf_set_keymap(buf_id, 'n', 'o',
    string.format(":lua vim.ui.open('%s'); require('github-projects.ui').close_current_popup()<CR>",
      safe_tostring(issue.html_url)),
    { noremap = true, silent = true })
end

-- Função para criar issue (usando vim.ui.select e vim.ui.input)
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
      prompt = "Selecione o Repositório:",
      format_item = function(item) return item end,
    }, function(selected_repo)
      if not selected_repo then
        vim.notify("Criação de issue cancelada.", vim.log.levels.INFO)
        return
      end

      vim.ui.input({ prompt = "Título da Issue: " }, function(issue_title)
        if not issue_title or issue_title == "" then
          vim.notify("Título é obrigatório. Criação de issue cancelada.", vim.log.levels.ERROR)
          return
        end

        vim.ui.input({ prompt = "Descrição (opcional): " }, function(issue_body)
          callback({
            repo = selected_repo,
            title = issue_title,
            body = issue_body or ""
          })
        end)
      end)
    end)
  end)
end

-- Funções de exibição de repositórios (usando vim.ui.select)
function M.show_repositories(repos)
  if not repos or #repos == 0 then
    vim.notify("Nenhum repositório encontrado", vim.log.levels.WARN)
    return
  end

  local items = {}
  for i, repo in ipairs(repos) do
    local repo_name = safe_tostring(repo.name) or "Sem nome"
    local description = safe_tostring(repo.description) or "Sem descrição"
    local language = safe_tostring(repo.language) or "N/A"
    local stars = safe_tostring(repo.stargazers_count) or "0"
    local private_str = repo.private and "Sim" or "Não"
    local updated_at = safe_tostring(repo.updated_at)

    local display_text = string.format("%s (%s) - %s (Stars: %s, Private: %s, Updated: %s)",
      repo_name, language, description, stars, private_str, updated_at:sub(1, 10))
    table.insert(items, display_text)
  end

  vim.ui.select(items, {
    prompt = "Selecione um Repositório:",
    format_item = function(item) return item end,
  }, function(selected_item, idx)
    if selected_item then
      local repo = repos[idx]
      if repo and repo.html_url then
        vim.ui.open(repo.html_url)
      end
    end
  end)
end

return M
