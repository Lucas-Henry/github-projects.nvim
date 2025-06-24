local M = {}
local config = require('github-projects.config')
local api = require('github-projects.api')
local popup = require('nui.popup')

-- Helper for safe string conversion
local function safe_str(value)
  if value == nil or value == vim.NIL then
    return ""
  end
  if type(value) == "string" then
    return value
  end
  return tostring(value)
end

-- Get pull requests for a repository
function M.get_pull_requests(repo, callback)
  api.get_pull_requests(repo, callback)
end

-- Create a new pull request
function M.create_pull_request(pr_data, callback)
  api.create_pull_request(pr_data, callback)
end

-- Review a pull request (approve/reject)
function M.review_pull_request(repo, pr_number, review_data, callback)
  api.review_pull_request(repo, pr_number, review_data, callback)
end

-- Show pull request with fullscreen interface and diff view
function M.show_pull_request_fullscreen(pr, repo)
  local pr_popup = popup({
    position = "50%",
    size = "95%",
    border = {
      style = "rounded",
      text = {
        top = "PR #" .. safe_str(pr.number) .. ": " .. safe_str(pr.title),
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:GitHubProjectsBorder",
    },
    buf_options = {
      modifiable = true,
    },
    enter = true,
  })

  pr_popup:mount()

  -- Show loading message
  local bufnr = pr_popup.bufnr
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Loading PR diff..." })

  -- Get PR diff
  api.get_pull_request_diff(repo, pr.number, function(diff_content)
    local lines = {}

    -- Add PR info
    table.insert(lines, "╭─ Pull Request Information " .. string.rep("─", 50) .. "╮")
    table.insert(lines, "│ Title: " .. safe_str(pr.title))
    table.insert(lines, "│ Author: " .. safe_str(pr.user and pr.user.login or "Unknown"))
    table.insert(lines, "│ State: " .. safe_str(pr.state))
    table.insert(lines, "│ Base: " .. safe_str(pr.base and pr.base.ref or "Unknown"))
    table.insert(lines, "│ Head: " .. safe_str(pr.head and pr.head.ref or "Unknown"))
    table.insert(lines, "╰" .. string.rep("─", 70) .. "╯")
    table.insert(lines, "")

    if pr.body and pr.body ~= "" then
      table.insert(lines, "╭─ Description " .. string.rep("─", 55) .. "╮")
      local desc_lines = vim.split(safe_str(pr.body), "\n")
      for _, line in ipairs(desc_lines) do
        table.insert(lines, "│ " .. line)
      end
      table.insert(lines, "╰" .. string.rep("─", 70) .. "╯")
      table.insert(lines, "")
    end

    table.insert(lines, "╭─ Diff " .. string.rep("─", 62) .. "╮")

    if diff_content and diff_content ~= "" then
      local diff_lines = vim.split(diff_content, "\n")
      for _, line in ipairs(diff_lines) do
        table.insert(lines, line)
      end
    else
      table.insert(lines, "Unable to load diff")
    end

    table.insert(lines, "")
    table.insert(lines, "╭─ Actions " .. string.rep("─", 59) .. "╮")
    table.insert(lines, "│ Press 'a' to approve this PR")
    table.insert(lines, "│ Press 'r' to request changes")
    table.insert(lines, "│ Press 'q' to close")
    table.insert(lines, "╰" .. string.rep("─", 70) .. "╯")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    vim.api.nvim_buf_set_option(bufnr, 'readonly', true)
    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'diff')

    -- Apply syntax highlighting
    local ns_id = vim.api.nvim_create_namespace("GitHubProjectsPR")

    -- Highlight headers and diff content
    for i, line in ipairs(lines) do
      if line:match("^╭─") or line:match("^╰") or line:match("^│") then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitHubProjectsBorder", i - 1, 0, -1)
      elseif line:match("^@@") then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "DiffText", i - 1, 0, -1)
      elseif line:match("^%+") then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "DiffAdd", i - 1, 0, -1)
      elseif line:match("^%-") then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "DiffDelete", i - 1, 0, -1)
      end
    end

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

    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>',
      ":close<CR>",
      { noremap = true, silent = true })
  end)

  return pr_popup
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
