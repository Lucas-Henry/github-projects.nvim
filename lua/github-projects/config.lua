local M = {}

local default_config = {
  org = nil,
  token = nil,
  config_file = nil,
  keymaps = {
    projects = "<leader>gp",
    issues = "<leader>gi",
    create_issue = "<leader>gc",
    repos = "<leader>gr",
    pull_requests = "<leader>gpr",
    create_pr = "<leader>gpc"
  },
  ui = {
    width = 120,
    height = 30,
    border = "single",
    enable_horizontal_scroll = true,
    min_column_width = 25,
    markdown_preview = true,
    fullscreen_on_details = true,
  }
}

local config = {}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", default_config, opts or {})

  -- Load from config file if specified
  if config.config_file then
    M.load_from_file(config.config_file)
  end

  -- Fallback to environment variables
  if not config.org then
    config.org = vim.env.GITHUB_ORG or vim.env.GH_ORG
  end

  if not config.token then
    config.token = vim.env.GITHUB_TOKEN or vim.env.GH_TOKEN
  end
end

function M.load_from_file(file_path)
  local expanded_path = vim.fn.expand(file_path)
  local file = io.open(expanded_path, "r")

  if not file then
    vim.notify("Config file not found: " .. expanded_path, vim.log.levels.WARN)
    return
  end

  for line in file:lines() do
    line = line:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
    if line ~= "" and not line:match("^#") then
      local key, value = line:match("^([^=]+)=(.*)$")
      if key and value then
        key = key:gsub("^%s*(.-)%s*$", "%1")
        value = value:gsub("^%s*(.-)%s*$", "%1")

        if key == "org" or key == "GITHUB_ORG" or key == "GH_ORG" then
          config.org = value
        elseif key == "token" or key == "GITHUB_TOKEN" or key == "GH_TOKEN" then
          config.token = value
        end
      end
    end
  end

  file:close()
end

function M.get_org()
  return config.org
end

function M.get_token()
  return config.token
end

function M.get_ui_config()
  return config.ui
end

function M.get_keymaps()
  return config.keymaps
end

function M.get_config()
  return config
end

return M
