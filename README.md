# GitHub Projects Plugin
A Neovim plugin for managing GitHub Projects with a visual Kanban board interface.

## Features
- Visual Kanban board for GitHub Projects v2
- Dynamic status columns based on your GitHub Projects configuration
- View issue details with syntax highlighting
- Open issues in browser with a single keystroke
- Full keyboard navigation

## Showcase
![image](https://github.com/user-attachments/assets/03ba355a-2695-4e36-897d-e93d391de8b5)
![image](https://github.com/user-attachments/assets/17c20e65-09c5-438e-98b4-a5b820822c2a)

## Requirements
- Neovim >= 0.7.0
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) >= 0.3.0
- GitHub Personal Access Token with appropriate permissions
- Optional: [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons) for file icons

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

1. **Install the plugin:**
```lua
use {
  'Lucas-Henry/github-projects.nvim',
  requires = {
    'MunifTanjim/nui.nvim',
    'kyazdani42/nvim-web-devicons', -- optional, for icons
  }
}
```

2. **Add configuration to your init.lua:**
```lua
require('github-projects').setup({
  config_file = vim.fn.expand("~/.config/gh_access.conf"),
  keymaps = {
    projects = "<leader>gp",
    issues = "<leader>gi",
    create_issue = "<leader>gc"
  },
  ui = {
    width = 120,      -- Width of the popup windows
    height = 30,      -- Height of the popup windows
    border = "single" -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
  }
})
```

3. **Set up keymaps (add to your init.lua):**
```lua
-- GitHub Projects keymaps
vim.keymap.set('n', '<leader>gp', '<cmd>GitHubProjects<cr>', { desc = 'GitHub Projects' })
vim.keymap.set('n', '<leader>gi', '<cmd>GitHubIssues<cr>', { desc = 'GitHub Issues' })
vim.keymap.set('n', '<leader>gc', '<cmd>GitHubCreateIssue<cr>', { desc = 'Create GitHub Issue' })
vim.keymap.set('n', '<leader>gr', '<cmd>GitHubRepos<cr>', { desc = 'GitHub Repositories' })
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
  'Lucas-Henry/github-projects.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons', -- optional, for icons
  },
  config = function()
    require('github-projects').setup({
      config_file = vim.fn.expand("~/.config/gh_access.conf"),
      keymaps = {
        projects = "<leader>gp",
        issues = "<leader>gi",
        create_issue = "<leader>gc"
      },
      ui = {
        width = 120,      -- Width of the popup windows
        height = 30,      -- Height of the popup windows
        border = "single" -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
      }
    })
  end,
  keys = {
    { "<leader>gp", "<cmd>GitHubProjects<cr>",    desc = "GitHub Projects" },
    { "<leader>gi", "<cmd>GitHubIssues<cr>",      desc = "GitHub Issues" },
    { "<leader>gc", "<cmd>GitHubCreateIssue<cr>", desc = "Create GitHub Issue" },
    { "<leader>gr", "<cmd>GitHubRepos<cr>",       desc = "GitHub Repositories" },
  },
  cmd = { "GitHubProjects", "GitHubIssues", "GitHubCreateIssue", "GitHubRepos" }
}
```

## Setup

### Create a config file
```bash
nvim ~/.config/gh_access.conf
```

**Add your GitHub Personal Access Token & Organization name:**
```
org=your_org_name
token=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> **Note:** Make sure to replace `your_org_name` with your actual GitHub organization name and `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` with your real GitHub Personal Access Token.

## Configuration Options
```lua
require('github-projects').setup({
  config_file = vim.fn.expand("~/.config/gh_access.conf"), -- Path to config file
  keymaps = {
    projects = "<leader>gp",     -- Keymap for opening projects
    issues = "<leader>gi",       -- Keymap for opening issues
    create_issue = "<leader>gc"  -- Keymap for creating issues
  },
  ui = {
    width = 120,      -- Width of the popup windows
    height = 30,      -- Height of the popup windows
    border = "single" -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
  }
})
```

## Usage
The plugin provides several commands:
- `:GitHubProjects` - Show available GitHub Projects
- `:GitHubProjectsIssues` - Show issues for a specific repository (Soon)
- `:GitHubProjectsRepos` - Show available repositories (Soon)
- `:GitHubProjectsCreateIssue` - Create a new issue (Soon)

## Keyboard Shortcuts

### Kanban Board View
- `j/k` - Navigate up/down within a column
- `h/l` - Navigate left/right between columns
- `Enter` - Open selected issue details
- `q/Esc` - Close the current view

### Issue Detail View
- `j/k` - Scroll up/down
- `Ctrl-f/Ctrl-b` - Page down/up
- `Ctrl-d/Ctrl-u` - Half page down/up
- `o` - Open issue in browser
- `b` - Return to Kanban board
- `q/Esc` - Close the issue view

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

## License
GNU license.
