local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

-- Importa os módulos do nui.nvim
local popup = require('nui.popup')
local menu = require('nui.menu')
local input = require('nui.input')
local layout = require('nui.layout')
local event = require('nui.utils.event')
local ffi = require('ffi') -- Para usar ffi.cast para o callback de menu

vim.notify("DEBUG: ui_nui.lua file loaded (using nui.nvim)", vim.log.levels.INFO)

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

-- Gerenciador de UI principal para nui.nvim
local NuiUI = {}
NuiUI.current_popup = nil
NuiUI.current_menu = nil
NuiUI.current_issues_data = nil -- Para o Kanban

function NuiUI.close_current_ui()
  if NuiUI.current_popup and NuiUI.current_popup.bufnr then
    NuiUI.current_popup:unmount()
    NuiUI.current_popup = nil
  end
  if NuiUI.current_menu and NuiUI.current_menu.bufnr then
    NuiUI.current_menu:unmount()
    NuiUI.current_menu = nil
  end
  NuiUI.current_issues_data = nil
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

-- Função para exibir projetos (usando nui.menu)
function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("Nenhum projeto encontrado", vim.log.levels.WARN)
    return
  end

  NuiUI.close_current_ui()

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
    table.insert(items, { text = display_text, value = project })
  end

  local ui_config = config.get_ui_config()

  NuiUI.current_menu = menu({
    items = items,
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "GitHub Projects",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  }, {
    on_close = function()
      NuiUI.current_menu = nil
    end,
    on_submit = ffi.cast("vim.menu_cb", function(item)
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
    end),
    max_width = ui_config.width,
    max_height = ui_config.height,
  })

  NuiUI.current_menu:mount()
end

-- Função para exibir issues em um formato Kanban-like (Open/Closed) usando nui.layout
function M.show_issues_kanban(issues, project_title)
  if not issues or #issues == 0 then
    vim.notify("Nenhuma issue encontrada", vim.log.levels.WARN)
    return
  end

  NuiUI.close_current_ui()

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
  local half_width = math.floor(ui_config.width / 2)

  -- Cria os buffers para as colunas
  local open_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(open_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(open_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(open_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(open_buf, 'filetype', 'github-projects-kanban')

  local closed_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(closed_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(closed_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(closed_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(closed_buf, 'filetype', 'github-projects-kanban')

  -- Preenche os buffers
  local open_lines = { "=== 🟢 OPEN ISSUES ===" }
  local open_issue_map = {}
  local open_line_idx = 1
  if #open_issues > 0 then
    for _, issue in ipairs(open_issues) do
      table.insert(open_lines, format_issue_line(issue))
      open_line_idx = open_line_idx + 1
      open_issue_map[open_line_idx] = issue
    end
  else
    table.insert(open_lines, "  (Nenhuma issue aberta)")
  end
  vim.api.nvim_buf_set_lines(open_buf, 0, -1, false, open_lines)

  local closed_lines = { "=== 🔴 CLOSED ISSUES ===" }
  local closed_issue_map = {}
  local closed_line_idx = 1
  if #closed_issues > 0 then
    for _, issue in ipairs(closed_issues) do
      table.insert(closed_lines, format_issue_line(issue))
      closed_line_idx = closed_line_idx + 1
      closed_issue_map[closed_line_idx] = issue
    end
  else
    table.insert(closed_lines, "  (Nenhuma issue fechada)")
  end
  vim.api.nvim_buf_set_lines(closed_buf, 0, -1, false, closed_lines)

  -- Armazena os mapas de issues para seleção
  NuiUI.current_issues_data = {
    open = open_issue_map,
    closed = closed_issue_map,
  }

  -- Cria o layout de colunas
  NuiUI.current_popup = popup({
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
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
    },
  }, {
    -- Define o layout interno
    mount = function(win)
      layout.split({
        layout.box({
          bufnr = open_buf,
          border = {
            style = "single",
            text = {
              top = "Open",
              top_align = "center",
            },
          },
          win_options = {
            winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
            cursorline = true,
          },
        }),
        layout.box({
          bufnr = closed_buf,
          border = {
            style = "single",
            text = {
              top = "Closed",
              top_align = "center",
            },
          },
          win_options = {
            winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
            cursorline = true,
          },
        }),
      }, {
        direction = "row",
        size = {
          width = { half_width, ui_config.width - half_width },
          height = ui_config.height,
        },
      }):mount(win)
    end,
    -- Keymaps para navegação e seleção
    on_key = function(key)
      if key == "q" or key == "<Esc>" then
        NuiUI.close_current_ui()
      elseif key == "<CR>" then
        local current_win = vim.api.nvim_get_current_win()
        local current_buf = vim.api.nvim_win_get_buf(current_win)
        local cursor_line = vim.api.nvim_win_get_cursor(current_win)[1] -- Linha base 1

        local selected_issue = nil
        if current_buf == open_buf then
          selected_issue = NuiUI.current_issues_data.open[cursor_line]
        elseif current_buf == closed_buf then
          selected_issue = NuiUI.current_issues_data.closed[cursor_line]
        end

        if selected_issue then
          M.show_issue_details(selected_issue)
        else
          vim.notify("Nenhuma issue selecionada nesta linha.", vim.log.levels.WARN)
        end
      elseif key == "l" then -- Mover para a direita (coluna Closed)
        local current_win = vim.api.nvim_get_current_win()
        local current_buf = vim.api.nvim_win_get_buf(current_win)
        if current_buf == open_buf then
          vim.api.nvim_set_current_win(vim.api.nvim_buf_get_option(closed_buf, 'winid'))
        end
      elseif key == "h" then -- Mover para a esquerda (coluna Open)
        local current_win = vim.api.nvim_get_current_win()
        local current_buf = vim.api.nvim_win_get_buf(current_win)
        if current_buf == closed_buf then
          vim.api.nvim_set_current_win(vim.api.nvim_buf_get_option(open_buf, 'winid'))
        end
      end
    end,
    on_close = function()
      NuiUI.current_popup = nil
      -- Garante que os buffers temporários sejam limpos
      if vim.api.nvim_buf_is_valid(open_buf) then vim.api.nvim_buf_delete(open_buf, { force = true }) end
      if vim.api.nvim_buf_is_valid(closed_buf) then vim.api.nvim_buf_delete(closed_buf, { force = true }) end
    end,
  })

  NuiUI.current_popup:mount()
end

-- Função para exibir detalhes de uma issue (usando nui.popup)
function M.show_issue_details(issue)
  NuiUI.close_current_ui() -- Fecha qualquer UI anterior

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

  local ui_config = config.get_ui_config()

  NuiUI.current_popup = popup({
    enter = true,
    focusable = true,
    relative = "editor",
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
  }, {
    on_key = function(key)
      if key == "q" or key == "<Esc>" then
        NuiUI.close_current_ui()
      elseif key == "o" then
        vim.ui.open(safe_tostring(issue.html_url))
        NuiUI.close_current_ui()
      end
    end,
    on_close = function()
      NuiUI.current_popup = nil
    end,
  })

  vim.api.nvim_buf_set_lines(NuiUI.current_popup.bufnr, 0, -1, false, lines)
  NuiUI.current_popup:mount()
end

-- Função para criar issue (usando nui.input e nui.menu)
function M.create_issue_form(callback)
  api.get_repositories(function(repos)
    if not repos or #repos == 0 then
      vim.notify("Nenhum repositório encontrado", vim.log.levels.ERROR)
      return
    end

    NuiUI.close_current_ui()

    local repo_items = {}
    for _, repo in ipairs(repos) do
      local repo_name = safe_tostring(repo.name)
      if repo_name then
        table.insert(repo_items, { text = repo_name, value = repo_name })
      end
    end

    NuiUI.current_menu = menu({
      items = repo_items,
      position = "50%",
      size = {
        width = 60,
        height = math.min(10, #repo_items + 2),
      },
      border = {
        style = "rounded",
        text = {
          top = "Selecione o Repositório",
          top_align = "center",
        },
      },
    }, {
      on_submit = ffi.cast("vim.menu_cb", function(item)
        if not item or not item.value then
          vim.notify("Criação de issue cancelada.", vim.log.levels.INFO)
          NuiUI.close_current_ui()
          return
        end
        local selected_repo = item.value
        NuiUI.close_current_ui() -- Fecha o menu de repositórios

        NuiUI.current_input_title = input({
          prompt = "Título da Issue: ",
          default_value = "",
          position = "50%",
          size = { width = 80 },
          border = { style = "rounded" },
        }, {
          on_submit = function(issue_title)
            if not issue_title or issue_title == "" then
              vim.notify("Título é obrigatório. Criação de issue cancelada.", vim.log.levels.ERROR)
              NuiUI.close_current_ui()
              return
            end
            NuiUI.current_input_title:unmount() -- Fecha o input de título

            NuiUI.current_input_body = input({
              prompt = "Descrição (opcional): ",
              default_value = "",
              position = "50%",
              size = { width = 80, height = 10 },
              border = { style = "rounded" },
              multiline = true,
            }, {
              on_submit = function(issue_body)
                callback({
                  repo = selected_repo,
                  title = issue_title,
                  body = issue_body or ""
                })
                NuiUI.close_current_ui()
              end,
              on_close = function()
                vim.notify("Criação de issue cancelada.", vim.log.levels.INFO)
                NuiUI.close_current_ui()
              end,
            })
            NuiUI.current_input_body:mount()
          end,
          on_close = function()
            vim.notify("Criação de issue cancelada.", vim.log.levels.INFO)
            NuiUI.close_current_ui()
          end,
        })
        NuiUI.current_input_title:mount()
      end),
      on_close = function()
        vim.notify("Criação de issue cancelada.", vim.log.levels.INFO)
        NuiUI.close_current_ui()
      end,
    })
    NuiUI.current_menu:mount()
  end)
end

-- Funções de exibição de repositórios (usando nui.menu)
function M.show_repositories(repos)
  if not repos or #repos == 0 then
    vim.notify("Nenhum repositório encontrado", vim.log.levels.WARN)
    return
  end

  NuiUI.close_current_ui()

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
    table.insert(items, { text = display_text, value = repo })
  end

  local ui_config = config.get_ui_config()

  NuiUI.current_menu = menu({
    items = items,
    position = "50%",
    size = {
      width = ui_config.width,
      height = ui_config.height,
    },
    border = {
      style = ui_config.border,
      text = {
        top = "GitHub Repositories",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
      cursorline = true,
    },
  }, {
    on_close = function()
      NuiUI.current_menu = nil
    end,
    on_submit = ffi.cast("vim.menu_cb", function(item)
      if item and item.value and item.value.html_url then
        vim.ui.open(item.value.html_url)
      end
    end),
    max_width = ui_config.width,
    max_height = ui_config.height,
  })

  NuiUI.current_menu:mount()
end

return M
