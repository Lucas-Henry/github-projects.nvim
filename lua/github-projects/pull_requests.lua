local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')
local popup = require('nui.popup')

-- Get pull requests for a repository
function M.get_pull_requests(repo, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    callback(nil)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/pulls?state=all&per_page=50", org, repo)

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  require('github-projects.api').curl_request(url, headers, nil, function(data, error)
    if error then
      vim.notify("Error loading pull requests: " .. error, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    callback(data or {})
  end)
end

-- Create a new pull request
function M.create_pull_request(pr_data, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token or not pr_data.repo then
    callback(false)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/pulls", org, pr_data.repo)

  local json_body = vim.json.encode({
    title = pr_data.title,
    body = pr_data.body or "",
    head = pr_data.head_branch,
    base = pr_data.base_branch
  })

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github+json",
    "Content-Type: application/json",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  require('github-projects.api').curl_request(url, headers, json_body, function(result, error)
    if error then
      vim.notify("Error creating pull request: " .. error, vim.log.levels.ERROR)
      callback(false)
      return
    end
    callback(result ~= nil)
  end)
end

-- Review a pull request (approve/reject)
function M.review_pull_request(repo, pr_number, review_data, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token or not repo or not pr_number then
    callback(false)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/pulls/%d/reviews", org, repo, pr_number)

  local json_body = vim.json.encode({
    body = review_data.body or "",
    event = review_data.event -- "APPROVE", "REQUEST_CHANGES", "COMMENT"
  })

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github+json",
    "Content-Type: application/json",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  require('github-projects.api').curl_request(url, headers, json_body, function(result, error)
    if error then
      vim.notify("Error reviewing pull request: " .. error, vim.log.levels.ERROR)
      callback(false)
      return
    end
    callback(result ~= nil)
  end)
end

-- Show pull request with fullscreen interface and diff view
function M.show_pull_request_fullscreen(pr, repo)
  local pr_popup = popup({
    position = "50%",
    size = "100%",
    border = {
      style = "rounded",
      text = {
        top = "PR #" .. tostring(pr.number) .. ": " .. (pr.title or ""),
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
    },
    buf_options = {
      modifiable = true,
    },
  })

  pr_popup:mount()

  -- Get PR diff
  M.get_pull_request_diff(repo, pr.number, function(diff_content)
    local bufnr = pr_popup.bufnr
    local lines = {}

    -- Add PR info
    table.insert(lines, "Title: " .. (pr.title or ""))
    table.insert(lines, "Author: " .. (pr.user and pr.user.login or "Unknown"))
    table.insert(lines, "State: " .. (pr.state or ""))
    table.insert(lines, "Base: " .. (pr.base and pr.base.ref or ""))
    table.insert(lines, "Head: " .. (pr.head and pr.head.ref or ""))
    table.insert(lines, "")
    table.insert(lines, "Description:")
    table.insert(lines, pr.body or "No description")
    table.insert(lines, "")
    table.insert(lines, "--- DIFF ---")

    if diff_content then
      local diff_lines = vim.split(diff_content, "\n")
      for _, line in ipairs(diff_lines) do
        table.insert(lines, line)
      end
    else
      table.insert(lines, "Unable to load diff")
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    vim.api.nvim_buf_set_option(bufnr, 'readonly', true)
    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'diff')

    -- Keymaps for PR actions
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'a',
      string.format(":lua require('github-projects.pull_requests').approve_pr('%s', %d)<CR>", repo, pr.number),
      { noremap = true, silent = true })

    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'r',
      string.format(":lua require('github-projects.pull_requests').reject_pr('%s', %d)<CR>", repo, pr.number),
      { noremap = true, silent = true })

    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q',
      ":close<CR>",
      { noremap = true, silent = true })
  end)

  return pr_popup
end

-- Get pull request diff
function M.get_pull_request_diff(repo, pr_number, callback)
  local org = config.get_org()
  local token = config.get_token()

  if not org or not token then
    callback(nil)
    return
  end

  local url = string.format("https://api.github.com/repos/%s/%s/pulls/%d", org, repo, pr_number)

  local headers = {
    "Authorization: Bearer " .. token,
    "Accept: application/vnd.github.v3.diff",
    "X-GitHub-Api-Version: 2022-11-28",
    "User-Agent: github-projects-nvim"
  }

  require('github-projects.api').curl_request(url, headers, nil, function(data, error)
    if error then
      vim.notify("Error loading PR diff: " .. error, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    callback(data)
  end)
end

-- Helper functions for PR actions
function M.approve_pr(repo, pr_number)
  vim.ui.input({ prompt = "Approval comment (optional): " }, function(comment)
    M.review_pull_request(repo, pr_number, {
      body = comment or "",
      event = "APPROVE"
    }, function(success)
      if success then
        vim.notify("Pull request approved successfully!", vim.log.levels.INFO)
      else
        vim.notify("Failed to approve pull request", vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.reject_pr(repo, pr_number)
  vim.ui.input({ prompt = "Rejection reason: " }, function(reason)
    if not reason or reason == "" then
      vim.notify("Rejection reason is required", vim.log.levels.ERROR)
      return
    end

    M.review_pull_request(repo, pr_number, {
      body = reason,
      event = "REQUEST_CHANGES"
    }, function(success)
      if success then
        vim.notify("Pull request changes requested!", vim.log.levels.INFO)
      else
        vim.notify("Failed to request changes", vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
