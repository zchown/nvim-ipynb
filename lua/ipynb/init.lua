local cell = require('ipynb.cell')
local kernel = require('ipynb.kernel')
local output = require('ipynb.output')
local notebook = require('ipynb.notebook')
local state = require('ipynb.state')

local M = {}

function M.run_cell()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_cell = cell.get_current_cell(bufnr)
  if not current_cell then
    return vim.notify("No cell", vim.log.levels.WARN)
  end

  local k = kernel.get_or_create(bufnr)
  if not k then return end

  local code = current_cell:get_content()
  k:execute(code, function(out)
    if #out > 0 then
      output.display(bufnr, current_cell, out, false)
    end
  end)
end

function M.run_all_cells()
  local bufnr = vim.api.nvim_get_current_buf()
  local cells = cell.parse_cells(bufnr)
  local i = 1
  
  local function run_next()
    if i > #cells then
      vim.notify("All cells done", vim.log.levels.INFO)
      return
    end
    vim.api.nvim_win_set_cursor(0, { cells[i].start_line, 0 })
    M.run_cell()
    i = i + 1
    vim.defer_fn(run_next, 500)
  end
  
  run_next()
end

function M.next_cell()
  cell.jump_to_next()
end

function M.prev_cell()
  cell.jump_to_prev()
end

function M.toggle_output()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_cell = cell.get_current_cell(bufnr)
  if not current_cell then
    return vim.notify("No cell", vim.log.levels.WARN)
  end
  output.toggle(bufnr, current_cell)
end

function M.close_output()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_cell = cell.get_current_cell(bufnr)
  if not current_cell then
    return vim.notify("No cell", vim.log.levels.WARN)
  end
  output.close(bufnr, current_cell)
end

function M.start_kernel()
  local bufnr = vim.api.nvim_get_current_buf()
  kernel.start(bufnr)
end

function M.stop_kernel()
  local bufnr = vim.api.nvim_get_current_buf()
  kernel.stop(bufnr)
end

function M.restart_kernel()
  M.stop_kernel()
  vim.defer_fn(M.start_kernel, 500)
end

function M.setup(opts)
  opts = opts or {}
  
  -- Setup highlights
  vim.api.nvim_set_hl(0, "JupyterCell", { fg = "#61AFEF", bold = true })
  vim.api.nvim_set_hl(0, "JupyterInlineOutput", { bg = "#264f78" })
  
  -- Setup signs
  vim.fn.sign_define("jupyter_cell", {
    text = "▎",
    texthl = "JupyterCell",
    linehl = "CursorLine"
  })
  
  -- Setup autocmds
  require('ipynb.autocmd').setup()
  
  -- Setup keymaps for notebooks
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "python", "ipynb" },
    callback = function()
      if vim.b.jupyter_notebook then
        local map_opts = { buffer = true, noremap = true, silent = true }
        vim.keymap.set("n", "<leader>rc", M.run_cell, map_opts)
        vim.keymap.set("n", "<leader>ra", M.run_all_cells, map_opts)
        vim.keymap.set("n", "<leader>ro", M.toggle_output, map_opts)
        vim.keymap.set("n", "<leader>rh", M.close_output, map_opts)
        vim.keymap.set("n", "]c", M.next_cell, map_opts)
        vim.keymap.set("n", "[c", M.prev_cell, map_opts)
        vim.keymap.set("n", "<leader>rk", M.start_kernel, map_opts)
        vim.keymap.set("n", "<leader>rK", M.stop_kernel, map_opts)
        vim.keymap.set("n", "<leader>rR", M.restart_kernel, map_opts)
      end
    end,
  })
end

return M
