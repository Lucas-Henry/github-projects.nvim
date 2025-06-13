local M = {}

M.defaults = {
  config_file = vim.fn.expand("~/.config/gh_access.conf"),
  auto_load = true,
  keymaps = {
    projects = "<leader>gp",
    issues = "<leader>gi",
    create_issue = "<leader>gc"
  },
  ui = {
    width = 80,
    height = 20,
    border = "rounded"
  }
}

M.config = vim.deepcopy(M.defaults)
M.credentials = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M.load_credentials()
end

function M.load_credentials()
  local config_file = M.config.config_file
  if not vim.fn.filereadable(config_file) then
    vim.notify("Config file not found: " .. config_file, vim.log.levels.ERROR)
    vim.notify("Create file with:\norg=your-organization\ntoken=your-token", vim.log.levels.INFO)
    return false
  end

  local lines = vim.fn.readfile(config_file)
  if not lines or #lines == 0 then
    vim.notify("Empty config file: " .. config_file, vim.log.levels.ERROR)
    return false
  end

  for _, line in ipairs(lines) do
    -- Skip empty lines and comments
    if line:match("^%s*$") or line:match("^%s*#") then
      goto continue
    end

    local key, value = line:match("^([^=]+)=(.*)$")
    if key and value then
      M.credentials[vim.trim(key)] = vim.trim(value)
    end
    ::continue::
  end

  return true
end

function M.validate()
  if not M.credentials.org or not M.credentials.token then
    vim.notify("Credentials not found. Check file: " .. M.config.config_file, vim.log.levels.ERROR)
    return false
  end

  if M.credentials.org == "" or M.credentials.token == "" then
    vim.notify("Empty credentials. Check file: " .. M.config.config_file, vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.get_org()
  return M.credentials.org
end

function M.get_token()
  return M.credentials.token
end

function M.get_ui_config()
  return M.config.ui
end

function M.debug()
  print("Config file:", M.config.config_file)
  print("Org:", M.credentials.org and "***" or "not set")
  print("Token:", M.credentials.token and "***" or "not set")
  print("UI config:", vim.inspect(M.config.ui))
end

return M
