# GitHub Projects.nvim

A Neovim plugin for managing GitHub Projects with a visual Kanban board interface.

## Features

- 📋 Visual Kanban board for GitHub Projects v2
- 🔄 Dynamic status columns based on your GitHub Projects configuration
- 🔍 View issue details with syntax highlighting
- 🌐 Open issues in browser with a single keystroke
- ⌨️ Full keyboard navigation

## Requirements

- Neovim >= 0.7.0
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) >= 0.3.0
- GitHub Personal Access Token with appropriate permissions
- Optional: [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons) for file icons

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'Lucas-Henry/github-projects.nvim',
  requires = {
    'MunifTanjim/nui.nvim',
    'kyazdani42/nvim-web-devicons', -- optional, for icons
  }
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'Lucas-Henry/github-projects.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons', -- optional, for icons
  },
  config = function()
    require('github-projects').setup({
      -- your configuration here
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

## Configuration

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

## Create a config file

```bash
nano ~/.config/gh_access.conf
```

Lay down your Github Personal Access Token & your Organization name

```
org=your_org_name
token=ghp.xxxxxxxxxx.xxxxx
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
