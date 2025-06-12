local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')

vim.notify("DEBUG: ui.lua file loaded", vim.log.levels.INFO)
vim.notify("DEBUG: Attempting to require nui in ui.lua", vim.log.levels.INFO)

-- Função de fallback para Nui components se nui não for carregado
local NuiFallback = {
  popup = function(opts)
    vim.notify("NuiPopup failed to load. Using fallback message. Error: " .. (opts.title or ""), vim.log.levels.ERROR)
    vim.api.nvim_echo({ { "Erro: Nui não carregado. Veja logs para detalhes.", "Error" } }, true, {})
    return {
      set_component = function() end,
      mount = function() end,
      map = function() end,
      unmount = function() end,
    }
  end,
  list = function(opts)
    vim.notify("NuiList failed to load. Error: " .. (opts.header and opts.header.text or ""), vim.log.levels.ERROR)
    return {
      mount = function() end,
      focus = function() end,
    }
  end,
  input = function(opts)
    vim.notify("NuiInput failed to load. Error: " .. (opts.prompt or ""), vim.log.levels.ERROR)
    return {
      mount = function() end,
    }
  end,
  text = function(opts)
    vim.notify("NuiText failed to load.", vim.log.levels.ERROR)
    return {
      mount = function() end,
    }
  end,
  split = function(opts)
    vim.notify("NuiSplit failed to load.", vim.log.levels.ERROR)
    return {
      mount = function() end,
      focus = function() end,
      focus_prev = function() end,
      focus_next = function() end,
    }
  end,
}

local success_nui, nui_module = pcall(require, 'nui')
local NuiPopup, NuiList, NuiInput, NuiText, NuiSplit

if success_nui then
  vim.notify("DEBUG: nui required successfully in ui.lua", vim.log.levels.INFO)
  NuiPopup = nui_module.popup
  NuiList = nui_module.list
  NuiInput = nui_module.input
  NuiText = nui_module.text
  NuiSplit = nui_module.split
else
  vim.notify("ERROR: Failed to load nui.nvim. UI functionality will be limited. Error: " .. nui_module,
    vim.log.levels.ERROR)
  NuiPopup = NuiFallback.popup
  NuiList = NuiFallback.list
  NuiInput = NuiFallback.input
  NuiText = NuiFallback.text
  NuiSplit = NuiFallback.split
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
  -- Adicione uma verificação para nui_module existir antes de tentar configurar hl_group
  if success_nui then
    vim.api.nvim_set_hl(0, "GitHubProjectsBorder", { fg = "#61AFEF", bg = "NONE" })                   -- Azul para borda
    vim.api.nvim_set_hl(0, "GitHubProjectsTitle", { fg = "#98C379", bg = "NONE", bold = true })       -- Verde para títulos
    vim.api.nvim_set_hl(0, "GitHubProjectsSelected", { fg = "#C678DD", bg = "#3E4452", bold = true }) -- Roxo para item selecionado
    vim.api.nvim_set_hl(0, "GitHubProjectsInfo", { fg = "#ABB2BF", bg = "NONE" })                     -- Cinza claro para informações
    vim.api.nvim_set_hl(0, "GitHubProjectsURL", { fg = "#56B6C2", bg = "NONE", underline = true })    -- Ciano para URLs
    vim.api.nvim_set_hl(0, "GitHubProjectsLabel", { fg = "#E5C07B", bg = "#3E4452" })                 -- Amarelo para labels
    vim.api.nvim_set_hl(0, "GitHubProjectsOpen", { fg = "#98C379", bg = "NONE", bold = true })        -- Verde para issues abertas
    vim.api.nvim_set_hl(0, "GitHubProjectsClosed", { fg = "#E06C75", bg = "NONE", bold = true })      -- Vermelho para issues fechadas
    vim.api.nvim_set_hl(0, "GitHubProjectsHeader", { fg = "#61AFEF", bg = "#282C34", bold = true })   -- Azul para cabeçalhos de coluna
  else
    vim.notify("Nui.nvim não carregado, pulando configuração de destaques.", vim.log.levels.WARN)
  end
end

setup_highlights()

-- Gerenciador de UI principal
local GitHubProjectsUI = {}
GitHubProjectsUI.current_popup = nil
GitHubProjectsUI.current_view = nil
GitHubProjectsUI.current_data = nil

function GitHubProjectsUI.close_current_popup()
  if GitHubProjectsUI.current_popup then
    GitHubProjectsUI.current_popup:unmount()
    GitHubProjectsUI.current_popup = nil
    GitHubProjectsUI.current_view = nil
    GitHubProjectsUI.current_data = nil
  end
end

function GitHubProjectsUI.open_popup(opts, on_close_callback)
  GitHubProjectsUI.close_current_popup() -- Fecha qualquer popup existente

  local ui_config = config.get_ui_config()
  local width = opts.width or ui_config.width
  local height = opts.height or ui_config.height

  local popup_opts = {
    enter = true,
    focusable = true,
    relative = 'editor',
    border = {
      style = ui_config.border,
      text = {
        top = opts.title or "GitHub Projects",
        top_align = "center",
      },
      padding = { 1, 1 },
      size = { width, height },
    },
    position = {
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
    },
    buf_options = {
      filetype = "github-projects",
    },
    on_close = function()
      if on_close_callback then
        on_close_callback()
      end
      GitHubProjectsUI.current_popup = nil
      GitHubProjectsUI.current_view = nil
      GitHubProjectsUI.current_data = nil
    end,
  }

  local popup_instance = NuiPopup(popup_opts) -- Use a variável local NuiPopup
  popup_instance:mount()

  -- Keymaps globais para o popup
  popup_instance:map('n', { 'q', '<Esc>' }, GitHubProjectsUI.close_current_popup, { noremap = true, silent = true })

  GitHubProjectsUI.current_popup = popup_instance -- Armazenar a instância
  return popup_instance
end

-- Função para exibir projetos
function M.show_projects(projects)
  if not projects or #projects == 0 then
    vim.notify("Nenhum projeto encontrado", vim.log.levels.WARN)
    return
  end

  GitHubProjectsUI.current_view = "projects"
  GitHubProjectsUI.current_data = projects

  local items = {}
  for i, project in ipairs(projects) do
    local title = safe_tostring(project.title) or "Sem título"
    local number = safe_tostring(project.number) or "N/A"
    local short_desc = safe_tostring(project.shortDescription)
    local updated_at = safe_tostring(project.updatedAt)

    local display_text = string.format("  %s (#%s) - %s", title, number, short_desc or "Sem descrição")
    if updated_at then
      display_text = display_text .. " (Atualizado: " .. updated_at:sub(1, 10) .. ")"
    end

    table.insert(items, {
      text = display_text,
      value = project,
      extmark_opts = { hl_group = "GitHubProjectsInfo" }
    })
  end

  local list_popup = GitHubProjectsUI.open_popup({
    title = "GitHub Projects V2",
    height = math.min(config.get_ui_config().height, #items + 6),
    width = config.get_ui_config().width,
  })

  local list_component = NuiList({
    items = items,
    max_height = math.min(config.get_ui_config().height - 6, #items),
    keymaps = {
      ['<CR>'] = function(item)
        if item and item.value then
          vim.notify("Carregando issues para o projeto: " .. item.value.title, vim.log.levels.INFO)
          api.get_issues(nil, function(issues)
            if issues then
              M.show_issues_kanban(issues, item.value.title)
            else
              vim.notify("Erro ao carregar issues para o projeto.", vim.log.levels.ERROR)
            end
          end)
        end
      end,
      ['o'] = function(item) -- Abrir URL do projeto
        if item and item.value and item.value.url then
          vim.ui.open(item.value.url)
          GitHubProjectsUI.close_current_popup()
        end
      end,
    },
    win_options = {
      winhighlight = "Normal:Normal,NuiList:GitHubProjectsInfo,NuiListSelected:GitHubProjectsSelected",
    },
  })

  list_popup:set_component(list_component)
  list_component:mount()
end

-- Função para exibir issues em um formato Kanban-like (Open/Closed)
function M.show_issues_kanban(issues, project_title)
  if not issues or #issues == 0 then
    vim.notify("Nenhuma issue encontrada", vim.log.levels.WARN)
    return
  end

  GitHubProjectsUI.current_view = "issues_kanban"
  GitHubProjectsUI.current_data = issues

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

  local open_items = {}
  for _, issue in ipairs(open_issues) do
    table.insert(open_items, {
      text = format_issue_line(issue),
      value = issue,
      extmark_opts = { hl_group = "GitHubProjectsOpen" }
    })
  end

  local closed_items = {}
  for _, issue in ipairs(closed_issues) do
    table.insert(closed_items, {
      text = format_issue_line(issue),
      value = issue,
      extmark_opts = { hl_group = "GitHubProjectsClosed" }
    })
  end

  local ui_config = config.get_ui_config()
  local popup_height = ui_config.height
  local popup_width = ui_config.width

  local split_popup = GitHubProjectsUI.open_popup({
    title = "Issues for " .. (project_title or "Organization"),
    height = popup_height,
    width = popup_width,
  })

  local current_list_component = nil -- Para controlar qual lista está focada

  local function create_issue_list(items, title_text, hl_group_item)
    return NuiList({
      items = items,
      max_height = popup_height - 6, -- Ajustar para o cabeçalho e borda
      keymaps = {
        ['<CR>'] = function(item)
          if item and item.value then
            M.show_issue_details(item.value)
          end
        end,
        ['t'] = function(item) -- Toggle state (open/closed)
          if item and item.value then
            local new_state = (item.value.state == "open") and "closed" or "open"
            local repo_name = item.value.repository_url:match("github.com/[^/]+/(.+)/issues") -- Extrai repo do URL
            if repo_name then
              vim.notify("Atualizando issue #" .. item.value.number .. " para " .. new_state .. "...",
                vim.log.levels.INFO)
              api.update_issue_state(repo_name, item.value.number, new_state, function(success)
                if success then
                  vim.notify("Issue #" .. item.value.number .. " atualizada para " .. new_state, vim.log.levels.INFO)
                  -- Recarregar issues para refletir a mudança
                  api.get_issues(nil, function(updated_issues)
                    if updated_issues then
                      M.show_issues_kanban(updated_issues, project_title)
                    end
                  end)
                else
                  vim.notify("Falha ao atualizar issue #" .. item.value.number, vim.log.levels.ERROR)
                end
              end)
            else
              vim.notify("Não foi possível determinar o repositório da issue.", vim.log.levels.ERROR)
            end
          end
        end,
        ['o'] = function(item) -- Abrir URL da issue
          if item and item.value and item.value.html_url then
            vim.ui.open(item.value.html_url)
            GitHubProjectsUI.close_current_popup()
          end
        end,
      },
      win_options = {
        winhighlight = "Normal:Normal,NuiList:GitHubProjectsInfo,NuiListSelected:GitHubProjectsSelected",
      },
      header = {
        text = title_text,
        text_opts = { hl_group = "GitHubProjectsHeader" },
      },
    })
  end

  local open_list = create_issue_list(open_items, "🟢 Open Issues", "GitHubProjectsOpen")
  local closed_list = create_issue_list(closed_items, "🔴 Closed Issues", "GitHubProjectsClosed")

  local split_component = NuiSplit({
    dir = 'row',
    relative = 'container',
    components = {
      {
        size = '50%',
        component = open_list,
      },
      {
        size = '50%',
        component = closed_list,
      },
    },
    keymaps = {
      ['h'] = function() split_component:focus_prev() end,
      ['l'] = function() split_component:focus_next() end,
    },
  })

  split_popup:set_component(split_component)
  split_component:mount()
  split_component:focus() -- Foca no primeiro componente (Open Issues)
end

-- Função para exibir detalhes de uma issue
function M.show_issue_details(issue)
  local lines = {
    { text = "=== DETALHES DA ISSUE ===",                                        opts = { hl_group = "GitHubProjectsTitle" } },
    "",
    { text = string.format("Título: %s", safe_tostring(issue.title) or "N/A"),   opts = { hl_group = "GitHubProjectsInfo" } },
    { text = string.format("Número: #%s", safe_tostring(issue.number) or "N/A"), opts = { hl_group = "GitHubProjectsInfo" } },
    { text = string.format("Estado: %s", safe_tostring(issue.state) or "N/A"),   opts = { hl_group = issue.state == "open" and "GitHubProjectsOpen" or "GitHubProjectsClosed" } },
  }

  if issue.labels and #issue.labels > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels) do
      table.insert(labels, safe_tostring(label.name))
    end
    table.insert(lines, { text = "Labels: " .. table.concat(labels, ", "), opts = { hl_group = "GitHubProjectsLabel" } })
  end

  if issue.assignee and issue.assignee.login then
    table.insert(lines,
      { text = "Assignee: " .. safe_tostring(issue.assignee.login), opts = { hl_group = "GitHubProjectsInfo" } })
  end

  if issue.user and issue.user.login then
    table.insert(lines,
      { text = "Autor: " .. safe_tostring(issue.user.login), opts = { hl_group = "GitHubProjectsInfo" } })
  end

  table.insert(lines,
    { text = "URL: " .. safe_tostring(issue.html_url) or "N/A", opts = { hl_group = "GitHubProjectsURL" } })
  table.insert(lines, "")
  table.insert(lines, { text = "Descrição:", opts = { hl_group = "GitHubProjectsTitle" } })
  table.insert(lines, "")

  -- Adicionar corpo da issue, que pode ser longo
  local body_lines = vim.split(safe_tostring(issue.body) or "Sem descrição.", "\n")
  for _, line in ipairs(body_lines) do
    table.insert(lines, { text = line, opts = { hl_group = "GitHubProjectsInfo" } })
  end

  local detail_popup = GitHubProjectsUI.open_popup({
    title = "Issue #" .. safe_tostring(issue.number),
    height = math.min(config.get_ui_config().height, #lines + 4),
    width = config.get_ui_config().width,
  })

  local text_component = NuiText({
    lines = lines,
    max_height = math.min(config.get_ui_config().height - 4, #lines),
    win_options = {
      winhighlight = "Normal:Normal",
    },
    keymaps = {
      ['o'] = function() -- Abrir URL da issue
        if issue.html_url then
          vim.ui.open(issue.html_url)
          GitHubProjectsUI.close_current_popup()
        end
      end,
    },
  })

  detail_popup:set_component(text_component)
  text_component:mount()
end

-- Função para criar issue
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
        table.insert(repo_names, { text = repo_name, value = repo_name })
      end
    end

    local ui_config = config.get_ui_config()
    local form_width = math.min(ui_config.width, 60)
    local form_height = 15

    local form_popup = GitHubProjectsUI.open_popup({
      title = "Criar Nova Issue",
      height = form_height,
      width = form_width,
    })

    local selected_repo = nil
    local issue_title = nil
    local issue_body = nil

    local function show_repo_select()
      local repo_select = NuiList({
        items = repo_names,
        max_height = form_height - 6,
        keymaps = {
          ['<CR>'] = function(item)
            if item and item.value then
              selected_repo = item.value
              show_title_input()
            end
          end,
        },
        win_options = {
          winhighlight = "Normal:Normal,NuiList:GitHubProjectsInfo,NuiListSelected:GitHubProjectsSelected",
        },
        header = {
          text = "Selecione o Repositório:",
          text_opts = { hl_group = "GitHubProjectsHeader" },
        },
      })
      form_popup:set_component(repo_select)
      repo_select:mount()
    end

    local function show_title_input()
      local title_input = NuiInput({
        prompt = "Título da Issue: ",
        default_value = "",
        on_submit = function(value)
          issue_title = value
          if not issue_title or issue_title == "" then
            vim.notify("Título é obrigatório", vim.log.levels.ERROR)
            show_title_input() -- Reabre o input se vazio
            return
          end
          show_body_input()
        end,
        on_close = function()
          if not issue_title then GitHubProjectsUI.close_current_popup() end -- Fecha se cancelar no título
        end,
        win_options = {
          winhighlight = "Normal:Normal,NuiInput:GitHubProjectsInfo",
        },
      })
      form_popup:set_component(title_input)
      title_input:mount()
    end

    local function show_body_input()
      local body_input = NuiInput({
        prompt = "Descrição (opcional): ",
        default_value = "",
        on_submit = function(value)
          issue_body = value
          callback({
            repo = selected_repo,
            title = issue_title,
            body = issue_body or ""
          })
          GitHubProjectsUI.close_current_popup()
        end,
        on_close = function()
          if not issue_body then GitHubProjectsUI.close_current_popup() end -- Fecha se cancelar no corpo
        end,
        win_options = {
          winhighlight = "Normal:Normal,NuiInput:GitHubProjectsInfo",
        },
      })
      form_popup:set_component(body_input)
      body_input:mount()
    end

    show_repo_select()
  end)
end

-- Funções de exibição de repositórios (mantidas, mas podem ser melhoradas com NuiList)
function M.show_repositories(repos)
  if not repos or #repos == 0 then
    vim.notify("Nenhum repositório encontrado", vim.log.levels.WARN)
    return
  end

  GitHubProjectsUI.current_view = "repositories"
  GitHubProjectsUI.current_data = repos

  local items = {}
  for i, repo in ipairs(repos) do
    local repo_name = safe_tostring(repo.name) or "Sem nome"
    local description = safe_tostring(repo.description) or "Sem descrição"
    local language = safe_tostring(repo.language) or "N/A"
    local stars = safe_tostring(repo.stargazers_count) or "0"
    local private_str = repo.private and "Sim" or "Não"
    local updated_at = safe_tostring(repo.updated_at)

    local display_text = string.format("  %s (%s) - %s", repo_name, language, description)
    if updated_at then
      display_text = display_text .. " (Atualizado: " .. updated_at:sub(1, 10) .. ")"
    end

    table.insert(items, {
      text = display_text,
      value = repo,
      extmark_opts = { hl_group = "GitHubProjectsInfo" }
    })
  end

  local list_popup = GitHubProjectsUI.open_popup({
    title = "GitHub Repositories",
    height = math.min(config.get_ui_config().height, #items + 6),
    width = config.get_ui_config().width,
  })

  local list_component = NuiList({
    items = items,
    max_height = math.min(config.get_ui_config().height - 6, #items),
    keymaps = {
      ['<CR>'] = function(item)
        if item and item.value and item.value.html_url then
          vim.ui.open(item.value.html_url)
          GitHubProjectsUI.close_current_popup()
        end
      end,
    },
    win_options = {
      winhighlight = "Normal:Normal,NuiList:GitHubProjectsInfo,NuiListSelected:GitHubProjectsSelected",
    },
  })

  list_popup:set_component(list_component)
  list_component:mount()
end

return M
