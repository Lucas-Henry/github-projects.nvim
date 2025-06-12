local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Importar módulos do nui.nvim
local popup = require('nui.popup')
local menu = require('nui.menu')

vim.notify("DEBUG: ui_nui.lua file loaded (visual Kanban mode)", vim.log.levels.INFO)

-- Gerenciador de UI principal para nui.nvim
local GitHubProjectsNuiUI = {}
GitHubProjectsNuiUI.current_popup = nil
GitHubProjectsNuiUI.current_menu = nil
GitHubProjectsNuiUI.issue_map = {}
GitHubProjectsNuiUI.current_column = "open"
GitHubProjectsNuiUI.current_selection = 1
GitHubProjectsNuiUI.open_issues = {}
GitHubProjectsNuiUI.closed_issues = {}

function GitHubProjectsNuiUI.close_current_popup()
  if GitHubProjectsNuiUI.current_popup then
    GitHubProjectsNuiUI.current_popup:unmount()
    GitHubProjectsNuiUI.current_popup = nil
  end
  if GitHubProjectsNuiUI.current_menu then
    GitHubProjectsNuiUI.current_menu:unmount()
    GitHubProjectsNuiUI.current_menu = nil
  end
  GitHubProjectsNuiUI.issue_map = {}
  GitHubProjectsNuiUI.current_column = "open"
  GitHubProjectsNuiUI.current_selection = 1
  GitHubProjectsNuiUI.open_issues = {}
  GitHubProjectsNuiUI.closed_issues = {}
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
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanBorder", { fg = "#61AFEF", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanOpenHeader", { fg = "#98C379", bg = "#282C34", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanClosedHeader", { fg = "#E06C75", bg = "#282C34", bold = true })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanOpenItem", { fg = "#98C379", bg = "NONE" })
  vim.api.nvim_set_hl(0, "GitHubProjectsKanbanClosedItem", { fg = "#E06C75", bg = "NONE" })
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

-- Função para criar uma visualização Kanban visual usando caracteres Unicode
function M.show_issues_kanban(issues, project_title)
  if not issues or #issues == 0 then
    vim.notify("Nenhuma issue encontrada", vim.log.levels.WARN)
    return
  end

  GitHubProjectsNuiUI.close_current_popup()

  -- Separar issues por estado
  local open_issues = {}
  local closed_issues = {}

  for _, issue in ipairs(issues) do
    if issue.state == "open" then
      table.insert(open_issues, issue)
    else
      table.insert(closed_issues, issue)
    end
  end

  -- Armazenar issues para uso posterior
  GitHubProjectsNuiUI.open_issues = open_issues
  GitHubProjectsNuiUI.closed_issues = closed_issues

  local ui_config = config.get_ui_config()
  local popup_width = ui_config.width
  local popup_height = ui_config.height

  -- Calcular largura das colunas
  local column_width = math.floor((popup_width - 3) / 2) -- -3 para bordas e separador central

  -- Criar o popup
  GitHubProjectsNuiUI.current_popup = popup({
    position = "50%",
    size = {
      width = popup_width,
      height = popup_height,
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
      cursorline = false, -- Desativamos cursorline para controlar manualmente
    },
  })

  -- Montar o popup antes de adicionar conteúdo
  GitHubProjectsNuiUI.current_popup:mount()

  -- Agora vamos desenhar o Kanban
  M.render_kanban_view(column_width)

  -- Configurar keymaps para navegação
  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'j',
    ":lua require('github-projects.ui_nui')._move_selection('down')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'k',
    ":lua require('github-projects.ui_nui')._move_selection('up')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'h',
    ":lua require('github-projects.ui_nui')._move_selection('left')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'l',
    ":lua require('github-projects.ui_nui')._move_selection('right')<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<CR>',
    ":lua require('github-projects.ui_nui')._select_current_issue()<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', 'q',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(GitHubProjectsNuiUI.current_popup.bufnr, 'n', '<Esc>',
    ":lua require('github-projects.ui_nui').close_current_popup()<CR>",
    { noremap = true, silent = true })
end

-- Função para renderizar a visualização Kanban
function M.render_kanban_view(column_width)
  if not GitHubProjectsNuiUI.current_popup then
    return
  end

  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  local popup_width = GitHubProjectsNuiUI.current_popup.win_config.width
  local popup_height = GitHubProjectsNuiUI.current_popup.win_config.height

  -- Limpar o buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- Caracteres para desenhar o Kanban
  local top_left = "╭"
  local top_right = "╮"
  local bottom_left = "╰"
  local bottom_right = "╯"
  local horizontal = "─"
  local vertical = "│"
  local t_down = "┬"
  local t_up = "┴"
  local t_right = "├"
  local t_left = "┤"
  local cross = "┼"

  -- Desenhar o cabeçalho
  local header_line = top_left .. string.rep(horizontal, column_width) ..
      t_down .. string.rep(horizontal, column_width) .. top_right
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { header_line })

  -- Desenhar os títulos das colunas
  local open_title = "🟢 OPEN ISSUES"
  local closed_title = "🔴 CLOSED ISSUES"

  -- Centralizar os títulos
  local open_padding = math.floor((column_width - #open_title) / 2)
  local closed_padding = math.floor((column_width - #closed_title) / 2)

  local title_line = vertical .. string.rep(" ", open_padding) .. open_title ..
      string.rep(" ", column_width - open_padding - #open_title) ..
      vertical .. string.rep(" ", closed_padding) .. closed_title ..
      string.rep(" ", column_width - closed_padding - #closed_title) .. vertical
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { title_line })

  -- Desenhar a linha separadora abaixo dos títulos
  local separator_line = t_right .. string.rep(horizontal, column_width) ..
      cross .. string.rep(horizontal, column_width) .. t_left
  vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { separator_line })

  -- Preparar as linhas para as issues
  local max_issues = math.max(#GitHubProjectsNuiUI.open_issues, #GitHubProjectsNuiUI.closed_issues)
  local content_height = popup_height - 5 -- Cabeçalho (3) + Rodapé (2)
  local visible_issues = math.min(max_issues, content_height)

  -- Mapear issues para linhas
  GitHubProjectsNuiUI.issue_map = {}

  -- Desenhar as linhas de conteúdo
  for i = 1, visible_issues do
    local open_issue_text = ""
    local closed_issue_text = ""

    -- Texto para issue aberta
    if i <= #GitHubProjectsNuiUI.open_issues then
      local issue = GitHubProjectsNuiUI.open_issues[i]
      open_issue_text = "#" .. safe_tostring(issue.number) .. ": " ..
          (safe_tostring(issue.title):sub(1, column_width - 10) or "Sem título")

      -- Adicionar ao mapa de issues
      GitHubProjectsNuiUI.issue_map["open_" .. i] = issue
    end

    -- Texto para issue fechada
    if i <= #GitHubProjectsNuiUI.closed_issues then
      local issue = GitHubProjectsNuiUI.closed_issues[i]
      closed_issue_text = "#" .. safe_tostring(issue.number) .. ": " ..
          (safe_tostring(issue.title):sub(1, column_width - 10) or "Sem título")

      -- Adicionar ao mapa de issues
      GitHubProjectsNuiUI.issue_map["closed_" .. i] = issue
    end

    -- Preencher com espaços para alinhar
    open_issue_text = open_issue_text .. string.rep(" ", column_width - #open_issue_text)
    closed_issue_text = closed_issue_text .. string.rep(" ", column_width - #closed_issue_text)

    -- Adicionar linha ao buffer
    local content_line = vertical .. open_issue_text .. vertical .. closed_issue_text .. vertical
    vim.api.nvim_buf_set_lines(bufnr, 2 + i, 3 + i, false, { content_line })
  end

  -- Preencher linhas vazias restantes
  for i = visible_issues + 1, content_height do
    local empty_line = vertical .. string.rep(" ", column_width) ..
        vertical .. string.rep(" ", column_width) .. vertical
    vim.api.nvim_buf_set_lines(bufnr, 2 + i, 3 + i, false, { empty_line })
  end

  -- Desenhar o rodapé
  local footer_line = bottom_left .. string.rep(horizontal, column_width) ..
      t_up .. string.rep(horizontal, column_width) .. bottom_right
  vim.api.nvim_buf_set_lines(bufnr, popup_height - 2, popup_height - 1, false, { footer_line })

  -- Adicionar linha de ajuda
  local help_text = "Navegação: ←/→ (colunas) ↑/↓ (issues) | Enter: Selecionar | q/Esc: Sair"
  local help_padding = math.floor((popup_width - #help_text) / 2)
  local help_line = string.rep(" ", help_padding) .. help_text
  vim.api.nvim_buf_set_lines(bufnr, popup_height - 1, popup_height, false, { help_line })

  -- Aplicar highlights
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsKanban")

  -- Highlight para cabeçalhos
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanOpenHeader", 1, 1, column_width + 1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanClosedHeader", 1, column_width + 1, -2)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2, 0, -1)

  -- Highlight para rodapé
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", popup_height - 2, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsInfo", popup_height - 1, 0, -1)

  -- Highlight para issues
  for i = 1, visible_issues do
    -- Bordas
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2 + i, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2 + i, column_width + 1, column_width + 2)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2 + i, -1, -1)

    -- Issues abertas
    if i <= #GitHubProjectsNuiUI.open_issues then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanOpenItem", 2 + i, 1, column_width + 1)
    end

    -- Issues fechadas
    if i <= #GitHubProjectsNuiUI.closed_issues then
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanClosedItem", 2 + i, column_width + 2, -1)
    end
  end

  -- Highlight para linhas vazias restantes
  for i = visible_issues + 1, content_height do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2 + i, 0, 1)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2 + i, column_width + 1, column_width + 2)
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 2 + i, -1, -1)
  end

  -- Destacar a seleção atual
  M._highlight_selection()
end

-- Função para destacar a seleção atual
function M._highlight_selection()
  if not GitHubProjectsNuiUI.current_popup then
    return
  end

  local bufnr = GitHubProjectsNuiUI.current_popup.bufnr
  local column_width = math.floor((GitHubProjectsNuiUI.current_popup.win_config.width - 3) / 2)
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsKanbanSelection")

  -- Limpar highlights anteriores
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Calcular a linha da seleção atual
  local line_idx = 2 + GitHubProjectsNuiUI.current_selection

  -- Calcular a coluna da seleção atual
  local col_start, col_end
  if GitHubProjectsNuiUI.current_column == "open" then
    col_start = 1
    col_end = column_width + 1
  else -- closed
    col_start = column_width + 2
    col_end = -2
  end

  -- Aplicar highlight
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanSelected", line_idx, col_start, col_end)
end

-- Função para mover a seleção
function M._move_selection(direction)
  if not GitHubProjectsNuiUI.current_popup then
    return
  end

  local max_selection
  if GitHubProjectsNuiUI.current_column == "open" then
    max_selection = #GitHubProjectsNuiUI.open_issues
  else
    max_selection = #GitHubProjectsNuiUI.closed_issues
  end

  if direction == "up" then
    GitHubProjectsNuiUI.current_selection = math.max(1, GitHubProjectsNuiUI.current_selection - 1)
  elseif direction == "down" then
    GitHubProjectsNuiUI.current_selection = math.min(max_selection, GitHubProjectsNuiUI.current_selection + 1)
  elseif direction == "left" and GitHubProjectsNuiUI.current_column == "closed" then
    GitHubProjectsNuiUI.current_column = "open"
    GitHubProjectsNuiUI.current_selection = math.min(GitHubProjectsNuiUI.current_selection,
      #GitHubProjectsNuiUI.open_issues)
    if #GitHubProjectsNuiUI.open_issues == 0 then
      GitHubProjectsNuiUI.current_selection = 1
    end
  elseif direction == "right" and GitHubProjectsNuiUI.current_column == "open" then
    GitHubProjectsNuiUI.current_column = "closed"
    GitHubProjectsNuiUI.current_selection = math.min(GitHubProjectsNuiUI.current_selection,
      #GitHubProjectsNuiUI.closed_issues)
    if #GitHubProjectsNuiUI.closed_issues == 0 then
      GitHubProjectsNuiUI.current_selection = 1
    end
  end

  M._highlight_selection()
end

-- Função para selecionar a issue atual
function M._select_current_issue()
  if not GitHubProjectsNuiUI.current_popup then
    return
  end

  local issue_key = GitHubProjectsNuiUI.current_column .. "_" .. GitHubProjectsNuiUI.current_selection
  local selected_issue = GitHubProjectsNuiUI.issue_map[issue_key]

  if selected_issue then
    M.show_issue_details(selected_issue)
  else
    vim.notify("Nenhuma issue selecionada nesta posição.", vim.log.levels.WARN)
  end
end

-- Função para exibir detalhes de uma issue
function M.show_issue_details(issue)
  GitHubProjectsNuiUI.close_current_popup()

  local lines = {}

  -- Título e número
  table.insert(lines, "╭" .. string.rep("─", 60) .. "╮")
  table.insert(lines, "│ " .. string.rep(" ", 58) .. " │")

  local title = safe_tostring(issue.title) or "Sem título"
  local title_line = "│  " .. title
  title_line = title_line .. string.rep(" ", 59 - #title_line) .. "│"
  table.insert(lines, title_line)

  local number = "#" .. (safe_tostring(issue.number) or "N/A")
  local state = safe_tostring(issue.state) or "N/A"
  local state_icon = state == "open" and "🟢" or "🔴"
  local info_line = "│  " .. number .. " - " .. state_icon .. " " .. state:upper()
  info_line = info_line .. string.rep(" ", 59 - #info_line) .. "│"
  table.insert(lines, info_line)

  table.insert(lines, "│ " .. string.rep(" ", 58) .. " │")
  table.insert(lines, "├" .. string.rep("─", 60) .. "┤")

  -- Labels
  if issue.labels and #issue.labels > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels) do
      table.insert(labels, safe_tostring(label.name))
    end
    local labels_line = "│  Labels: " .. table.concat(labels, ", ")
    labels_line = labels_line .. string.rep(" ", 59 - #labels_line) .. "│"
    table.insert(lines, labels_line)
  else
    table.insert(lines, "│  Labels: Nenhuma" .. string.rep(" ", 43) .. "│")
  end

  -- Assignee e Autor
  local assignee_line = "│  Assignee: "
  if issue.assignee and issue.assignee.login then
    assignee_line = assignee_line .. safe_tostring(issue.assignee.login)
  else
    assignee_line = assignee_line .. "Nenhum"
  end
  assignee_line = assignee_line .. string.rep(" ", 59 - #assignee_line) .. "│"
  table.insert(lines, assignee_line)

  local author_line = "│  Autor: "
  if issue.user and issue.user.login then
    author_line = author_line .. safe_tostring(issue.user.login)
  else
    author_line = author_line .. "Desconhecido"
  end
  author_line = author_line .. string.rep(" ", 59 - #author_line) .. "│"
  table.insert(lines, author_line)

  table.insert(lines, "│ " .. string.rep(" ", 58) .. " │")

  -- URL
  local url_line = "│  URL: " .. (safe_tostring(issue.html_url) or "N/A")
  url_line = url_line .. string.rep(" ", 59 - #url_line) .. "│"
  table.insert(lines, url_line)

  table.insert(lines, "│ " .. string.rep(" ", 58) .. " │")
  table.insert(lines, "├" .. string.rep("─", 60) .. "┤")
  table.insert(lines, "│  Descrição:" .. string.rep(" ", 48) .. "│")
  table.insert(lines, "│ " .. string.rep(" ", 58) .. " │")

  -- Descrição
  local body_lines = vim.split(safe_tostring(issue.body) or "Sem descrição.", "\n")
  for _, line in ipairs(body_lines) do
    -- Quebrar linhas longas
    while #line > 56 do
      local display_line = line:sub(1, 56)
      line = line:sub(57)
      table.insert(lines, "│  " .. display_line .. string.rep(" ", 56 - #display_line) .. "  │")
    end
    table.insert(lines, "│  " .. line .. string.rep(" ", 56 - #line) .. "  │")
  end

  table.insert(lines, "│ " .. string.rep(" ", 58) .. " │")
  table.insert(lines, "├" .. string.rep("─", 60) .. "┤")
  table.insert(lines, "│  Pressione 'o' para abrir no navegador" .. string.rep(" ", 25) .. "│")
  table.insert(lines, "╰" .. string.rep("─", 60) .. "╯")

  local ui_config = config.get_ui_config()

  GitHubProjectsNuiUI.current_popup = popup({
    position = "50%",
    size = {
      width = 62,
      height = math.min(ui_config.height, #lines),
    },
    border = "none",
    win_options = {
      winhighlight = "Normal:Normal",
    },
  })

  GitHubProjectsNuiUI.current_popup:mount()
  GitHubProjectsNuiUI.current_popup:set_lines(lines)

  -- Aplicar highlights
  local ns_id = vim.api.nvim_create_namespace("GitHubProjectsIssueDetails")

  -- Título e cabeçalho
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanBorder", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsTitle", 2, 3, -2)

  if issue.state == "open" then
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanOpenItem", 3, 3, -2)
  else
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsKanbanClosedItem", 3, 3, -2)
  end

  -- URL
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsURL", 10, 8, -2)

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
