# nvim-ipynb

A Neovim plugin for working with Jupyter notebooks **directly as text**.

`nvim-ipynb` lets you open, edit, and execute `.ipynb` files inside Neovim by transparently converting them to a Python “percent format” (`# %%`) representation and back again. The goal is to stay as close as possible to the notebook execution model while keeping everything plain-text and editor-native.

## Features

- Open `.ipynb` files as editable Python files using `# %%` cell markers
- Execute cells against a real Jupyter kernel
- Per-notebook kernel lifecycle (start, stop, restart)
- Cell-aware navigation (`next` / `previous`)
- View cell output in floating windows or inline
- Persistent outputs per cell (toggleable)
- Automatic round-trip conversion using `jupytext`

## Non-Goals (by design)

- No custom notebook file format
- No attempt to reimplement the Jupyter UI
- No hidden cell state stored outside the buffer
- No magic cell insertion — `# %%` is the source of truth

If it’s in the buffer, it’s part of the notebook.

## Requirements

- Neovim 0.8+
- Python with Jupyter installed  
  ```sh
  pip install jupyter


  ```sh
  pip install jupytext
  ```

Optional (for rich output):

* [`image.nvim`](https://github.com/3rd/image.nvim) for rendering images/plots

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "zchown/nvim-ipynb",
  ft = { "ipynb", "python" },
  config = function()
    require("ipynb").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "zchown/nvim-ipynb",
  ft = { "ipynb", "python" },
  config = function()
    require("ipynb").setup()
  end,
}
```

## Usage

### Cell Markers

Cells are delimited using standard Jupytext percent markers:

```python
# %%
import numpy as np
print("First cell")

# %%
x = np.array([1, 2, 3])
x
```

Typing `# %%` anywhere in the buffer creates a new cell boundary.
Nothing special is required — markers are parsed directly from the file.

### Default Keymaps

When editing a notebook (`.ipynb`):

* `<leader>rc` — Run current cell
* `<leader>ra` — Run all cells
* `<leader>ro` — Toggle output window for current cell
* `<leader>rh` — Close output window
* `]c` — Jump to next cell
* `[c` — Jump to previous cell
* `<leader>rk` — Start kernel
* `<leader>rK` — Stop kernel
* `<leader>rR` — Restart kernel

### Commands

* `:JupyterRunCell` — Execute the current cell
* `:JupyterRunAll` — Execute all cells sequentially
* `:JupyterToggleOutput` — Toggle output window for current cell
* `:JupyterCloseOutput` — Close output window for current cell
* `:JupyterNextCell` — Jump to next cell
* `:JupyterPrevCell` — Jump to previous cell
* `:JupyterStartKernel` — Start a Jupyter kernel
* `:JupyterStopKernel` — Stop the running kernel
* `:JupyterRestartKernel` — Restart the kernel
* `:IpynbKernels` — List available kernels
* `:IpynbKernel <argument>` — Set kernel by name

## Output Display

* **Floating output**
  Executing a cell opens a floating window showing that cell’s output.
  Press `q` or `<Esc>` to close.

* **Inline output**
  When enabled, previously executed cell output appears inline below the
  cell you are currently in.

Outputs are associated with cells, not buffers, and persist until replaced
or the buffer is wiped.

## Configuration

Minimal configuration for now. Only highlight customization is supported.

```lua
require("ipynb").setup()

vim.api.nvim_set_hl(0, "JupyterCell", { fg = "#61AFEF", bold = true })
vim.api.nvim_set_hl(0, "JupyterInlineOutput", { bg = "#264f78" })
```

More configuration options may be added later, but simplicity is a goal.

## How It Works

1. **Opening a notebook**
   When you open a `.ipynb` file, it is converted to Python using:

   ```sh
   jupytext --to py:percent
   ```

2. **Editing**
   You edit a normal Python buffer containing `# %%` cell markers.

3. **Execution**
   Code is sent to a Jupyter kernel via `jupyter console`. Output is captured
   and associated with the originating cell.

4. **Saving**
   On save, the Python buffer is converted back to `.ipynb` using `jupytext`.

At no point is notebook state hidden from the user — the buffer is the
notebook.

## License

MIT
