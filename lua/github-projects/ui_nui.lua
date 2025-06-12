local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Importar módulos do nui.nvim
local popup = require('nui.popup')
local menu = require('nui.menu')
-- Removido: local layout = require('nui.layout') -- Não compatível com 0.3.0 para layout complexo

vim.notify("DEBUG: ui_nui.lua file loaded (using nui.nvim)", vim.log.levels.INFO)

-- Gerenciador de UI principal para nui.nvim
local GitHubProjectsNuiUI = {}
GitHubProjectsNuiUI.current_popup = nil
GitHubProjectsNuiUI.current_menu = nil
-- Removido: GitHubProjectsNuiUI.current_kanban_layout = nil

function GitHubProjectsNuiUI.close_current_popup()
  if GitHubProjectsNuiUI.current_popup then
    GitHubProjectsNuiUI.current_popup:unmount()
    GitHubProjectsNuiUI.current_popup = nil
  end
  if GitHubProjectsNuiUI.current_menu then
    GitHubProjectsNuiUI.current_menu:unmount()
    GitHubProjectsNuiUI.current_menu = nil
  end
  -- Removido: if GitHubProjectsNuiUI.current_kanban_layout then
  -- Removido:   GitHubProjectsNuiUI.current_kanban_layout:unmount()
  -- Removido:   GitHubProjectsNuiUI.current_kanban_layout = nil
  -- Removido: end
end

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

-- Highlight groups para a UI
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
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanHeader", { fg = "#61AFEF", bg = "#282C34", bold = true, underline = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanItem", { fg = "#ABB2BF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanSelected", { fg = "#C678DD", bg = "#3E4452", bold = true })
end
setup_highlights()

-- Função para obter ícone de devicon (se disponível)
local function get_devicon(filename)
  local devicons_ok, devicons = pcall(require, 'nvim-web-devicons')
  if devicons_ok then
    local icon, hl = devicons.get_icon(filename)
    return icon or " "
  end
  return " "
end

-- Função para exibir projetos (usando nui.menu)
function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("Nenhum projeto encontrado", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  local items = {}
  for i, project in ipairs(projects) do
    local title = safe_tostring(project.title) or "Sem título"
    local number = safe_tostring(project.number) or "N/A"
    local short_desc = safe_tostring(project.shortDescription)
    local updated_at = safe_tostring(project.updatedAt)

    local icon = get_devicon("project.md") -- Ícone genérico para projeto
    local display_text = string.format("%s %s (#%s) - %s (Atualizado: %s)",
      icon, title, number, short_desc or "Sem descrição", updated_at and updated_at:sub(1, 10) or "N/A")

    table.insert(items, menu.item(display_text, { value = project }))
  end

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_menu = menu({
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Selecione um Projeto",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  }, {
    lines = items,
    max_width = ui_config.width,
    max_height = ui_config.height,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>", "q" },
      submit = { "<CR>", "<Space>" },
    },
    on_close = function()
      GitHubProjectsNuiUI.current_menu = nil
    end,
    on_submit = function(item)
      GitHubProjectsNuiUI.close_current_popup()
      if item and item.value then
        local project = item.value
        vim.notify("Carregando issues para o projeto: " .. project.title, vim.log.levels.INFO)
        api.get_issues(nil, function(issues)
          if issues then
            M.show_issues_kanban(issues, project.title)
          else
            vim.notify("Erro ao carregar issues para o projeto.", vim.log.levels.ERROR)
          end
        end)
      end
    end,
  })

  GitHubProjectsNuiUI.current_menu:mount()
end

-- Função para exibir issues em um formato Kanban-like (Open/Closed) usando um único popup
function M.show_issues_kanban(issues, project_title)
  if not issues or #issues == 0 then
    vim.notify("Nenhuma issue encontrada", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  local open_issues = {}
  local closed_issues = {}

  for _, issue in ipairs(issues) do
    if issue.state == "open" then
      table.insert(open_issues, issue)
    else
      table.insert(closed_issues, issue)
    end
  end

  local ui_config = config.get_ui_config()
  local popup_width = ui_config.width
  local popup_height = ui_config.height

  local lines = {}
  local issue_map = {} -- Mapeia o índice da linha para a issue real
  local current_line_idx = 0

  -- Helper para adicionar linha e mapear issue
  local function add_issue_line(issue)
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
    local line_text = string.format("%s #%s: %s%s", state_icon, number, title, labels_str)
    table.insert(lines, line_text)
    current_line_idx = current_line_idx + 1
    issue_map[current_line_idx] = issue
  end

  -- Adiciona cabeçalho de Open Issues
  table.insert(lines, "=== 🟢 OPEN ISSUES " .. string.rep("=", math.max(0, popup_width - 22))) -- Preenche com '='
  current_line_idx = current_line_idx + 1
  if #open_issues > 0 then
    for _, issue in ipairs(open_issues) do
      add_issue_line(issue)
    end
  else
    table.insert(lines, "  (Nenhuma issue aberta)")
    current_line_idx = current_line_idx + 1
  end
  table.insert(lines, "") -- Linha em branco para separação
  current_line_idx = current_line_idx + 1

  -- Adiciona cabeçalho de Closed Issues
  table.insert(lines, "=== 🔴 CLOSED ISSUES " .. string.rep("=", math.max(0, popup_width - 23))) -- Preenche com '='
  current_line_idx = current_line_idx + 1
  if #closed_issues > 0 then
    for _, issue in ipairs(closed_issues) do
      add_issue_line(issue)
    end
  else
    table.insert(lines, "  (Nenhuma issue fechada)")
    current_line_idx = current_line_idx + 1
  end

  GitHubProjectsNuiUI.current_popup = popup({
    position = "50%",
    size = {
      width = popup_width,
      height = math.min(popup_height, #lines + 4), -- Ajusta altura se houver poucas linhas
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Issues para: " .. project_title,
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
      number = false,
      relativenumber = false,
    },
  })

  GitHubProjectsNuiUI.current_popup:mount()
  GitHubProjectsNuiUI.current_popup:set_lines(lines)
  GitHubProjectsNuiUI.current_popup.issue_map = issue_map -- Armazena o mapa de issues

  -- Keymap para selecionar issue
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<CR>',
    ":lua require('github-projects.ui_nui')._handle_issue_selection_from_kanban()<CR>",
    { noremap = true, silent = true })

  -- Keymaps para fechar
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'q',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<Esc>',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })

  -- Remove keymaps de navegação entre colunas, pois não há colunas separadas
  GitHubProjectsNuiUI.kanban_menus = nil -- Limpa a referência
end

-- Função auxiliar para lidar com a seleção de issues no Kanban (ajustada para um único popup)
function M._handle_issue_selection_from_kanban()
  if not GitHubProjectsNuiUI.current_popup or not GitHubProjectsNuiUI.current_popup.issue_map then
    vim.notify("Erro: Popup de Kanban não encontrado.", vim.log.levels.ERROR)
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local cursor_line = vim.api.nvim_win_get_cursor(current_win)[1] -- Linha base 1
  local selected_issue = GitHubProjectsNuiUI.current_popup.issue_map[cursor_line]

  if selected_issue then
    M.show_issue_details(selected_issue)
  else
    vim.notify("Nenhuma issue selecionada nesta linha.", vim.log.levels.WARN)
  end
end

-- Função auxiliar para focar em uma coluna específica do Kanban (removida, pois não há colunas separadas)
-- function M._focus_kanban_column(column_name)
--   -- Esta função não é mais necessária com um único popup
-- end

-- Função para exibir detalhes de uma issue (usando nui.popup)
function M.show_issue_details(issue)
  GitHubProjectsNuiUI.close_current_popup()

  local lines = {}

  -- Título e número (usando strings simples)
  table.insert(lines, "=== DETALHES DA ISSUE ===")
  table.insert(lines, "")
  table.insert(lines, string.format("Título: %s", safe_tostring(issue.title) or "N/A"))
  table.insert(lines, string.format("Número: #%s", safe_tostring(issue.number) or "N/A"))
  table.insert(lines, string.format("Estado: %s", safe_tostring(issue.state) or "N/A"))

  -- Labels
  if issue.labels and #issue.labels > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels) do
      table.insert(labels, safe_tostring(label.name))
    end
    table.insert(lines, "Labels: " .. table.concat(labels, ", "))
  end

  -- Assignee e Autor
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

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_popup = popup({
    position = "50%",
    size = {
      width = ui_config.width,
      height = math.min(ui_config.height, #lines + 4),
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Issue #" .. safe_tostring(issue.number),
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  })

  GitHubProjectsNuiUI.current_popup:mount()
  GitHubProjectsNuiUI.current_popup:set_lines(lines)

  -- Keymap para abrir URL
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'o',
    string.format(":lua vim.ui.open('%s'); require('github-projects.ui_nui').close_current_popup()<CR>",
      safe_tostring(issue.html_url)),
    { noremap = true, silent = true })

  -- Keymap para fechar
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'q',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<Esc>',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
end

-- Função para criar issue (mantendo vim.ui.select e vim.ui.input por simplicidade)
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

-- Funções de exibição de repositórios (usando nui.menu)
function M.show_repositories(repos)
  if not repos or #repos == 0 then
    vim.notify("Nenhum repositório encontrado", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  local items = {}
  for i, repo in ipairs(repos) do
    local repo_name = safe_tostring(repo.name) or "Sem nome"
    local description = safe_tostring(repo.description) or "Sem descrição"
    local language = safe_tostring(repo.language) or "N/A"
    local stars = safe_tostring(repo.stargazers_count) or "0"
    local private_str = repo.private and "🔒 Private" or "🌐 Public"
    local updated_at = safe_tostring(repo.updated_at)

    local icon = get_devicon(repo_name .. "." .. language:lower()) -- Tenta ícone por linguagem
    if icon == " " then icon = get_devicon("folder") end           -- Fallback para ícone de folder

    local display_text = string.format("%s %s (%s) - %s | ⭐ %s | %s | Atualizado: %s",
      icon, repo_name, language, description, stars, private_str, updated_at and updated_at:sub(1, 10) or "N/A")

    table.insert(items, menu.item(display_text, { value = repo }))
  end

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_menu = menu({
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "Selecione um Repositório",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  }, {
    lines = items,
    max_width = ui_config.width,
    max_height = ui_config.height,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>", "q" },
      submit = { "<CR>", "<Space>" },
    },
    on_close = function()
      GitHubProjectsNuiUI.current_menu = nil
    end,
    on_submit = function(item)
      GitHubProjectsNuiUI.close_current_popup()
      if item and item.value and item.value.html_url then
        vim.ui.open(item.value.html_url)
      end
    end,
  })

  GitHubProjectsNuiUI.current_menu:mount()
end

-- Função para fechar popup (disponível publicamente)
M.close_current_popup = GitHubProjectsNuiUI.close_current_popup

return M
