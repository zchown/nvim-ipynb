# nvim-ipynb

A Neovim plugin for working with Jupyter notebooks directly in your editor.

## Features

- Open and edit `.ipynb` files as Python files with cell markers
- Execute cells using Jupyter kernels
- View cell output in floating or inline windows
- Navigate between cells
- Auto-show inline output for the current cell
- Full kernel management (start, stop, restart)

## Requirements

- Neovim 0.8+
- Python with Jupyter installed (`pip install jupyter`)
- jupytext (`pip install jupytext`)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/nvim-ipynb",
  ft = { "ipynb", "python" },
  config = function()
    require("ipynb").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/nvim-ipynb",
  ft = { "ipynb", "python" },
  config = function()
    require("ipynb").setup()
  end,
}
```

## Directory Structure

```
nvim-ipynb/
├── plugin/
│   └── ipynb.lua            # Plugin entry point, registers commands
├── lua/
│   └── ipynb/
│       ├── init.lua         # Main module, public API
│       ├── state.lua        # Centralized state management
│       ├── cell.lua         # Cell parsing and navigation
│       ├── kernel.lua       # Jupyter kernel management
│       ├── output.lua       # Output window management
│       ├── notebook.lua     # Notebook I/O (jupytext integration)
│       └── autocmd.lua      # Autocommands for notebook files
└── README.md
```

## Usage

### Cell Markers

Cells are delimited by `# %%` markers in the Python file:

```python
# %%
import numpy as np
print("First cell")

# %%
x = np.array([1, 2, 3])
print(x)
```

### Default Keymaps

When editing a notebook (`.ipynb` file), the following keymaps are available:

- `<leader>rc` - Run current cell
- `<leader>ra` - Run all cells
- `<leader>ro` - Toggle output window
- `<leader>rh` - Close output window
- `]c` - Jump to next cell
- `[c` - Jump to previous cell
- `<leader>rk` - Start kernel
- `<leader>rK` - Stop kernel
- `<leader>rR` - Restart kernel

### Commands

- `:JupyterRunCell` - Execute the current cell
- `:JupyterRunAll` - Execute all cells sequentially
- `:JupyterToggleOutput` - Toggle output window for current cell
- `:JupyterCloseOutput` - Close output window for current cell
- `:JupyterNextCell` - Jump to next cell
- `:JupyterPrevCell` - Jump to previous cell
- `:JupyterStartKernel` - Start a Jupyter kernel
- `:JupyterStopKernel` - Stop the running kernel
- `:JupyterRestartKernel` - Restart the kernel

### Output Display

- **Floating windows**: When you run a cell, output appears in a centered floating window. Press `q` or `<Esc>` to close.
- **Inline output**: As you move between cells, inline output automatically appears below the cell you're in (if that cell has been executed).

## Configuration

The plugin works out of the box with sensible defaults. You can customize highlights in your config:

```lua
require("ipynb").setup()

-- Customize highlights
vim.api.nvim_set_hl(0, "JupyterCell", { fg = "#61AFEF", bold = true })
vim.api.nvim_set_hl(0, "JupyterInlineOutput", { bg = "#264f78" })
```

## How It Works

1. **File Loading**: When you open a `.ipynb` file, the plugin uses `jupytext` to convert it to a Python file with `# %%` cell markers
2. **Kernel Management**: The plugin starts a Jupyter kernel using `jupyter console` when you first run a cell
3. **Execution**: Code is sent to the kernel via job control, and output is captured and displayed
4. **File Saving**: When you save, the Python file is converted back to `.ipynb` format

## Architecture

The plugin is organized into focused modules:

- **state.lua**: Central store for all plugin state (kernels, cells, outputs)
- **cell.lua**: Cell parsing, navigation, and sign management
- **kernel.lua**: Jupyter kernel lifecycle and code execution
- **output.lua**: Window creation and output display logic
- **notebook.lua**: File I/O with jupytext integration
- **autocmd.lua**: Autocommand setup for notebook behavior
- **init.lua**: Public API that ties everything together

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT
