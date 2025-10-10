local cell = require('ipynb.cell')
local notebook = require('ipynb.notebook')
local output = require('ipynb.output')

local M = {}

function M.setup()
  -- Load .ipynb files
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "*.ipynb",
    callback = function(args)
      local notebook_path = vim.fn.fnamemodify(args.file, ":p")
      local content = notebook.load(notebook_path)
      
      if not content then return end
      
      vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
      vim.b.jupyter_notebook = notebook_path
      vim.bo.swapfile = false
      vim.bo.modifiable = true
      
      vim.defer_fn(function()
        vim.bo.filetype = "python"
      end, 10)
      
      vim.defer_fn(function()
        cell.parse_cells(0)
        cell.update_signs(0)
      end, 100)
    end,
  })
  
  -- Save .ipynb files
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = "*.ipynb",
    callback = function()
      notebook.save(0, vim.b.jupyter_notebook)
    end,
  })
  
  -- Update cells and signs on text change
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    pattern = "*.ipynb",
    callback = function()
      if vim.b.jupyter_notebook then
        cell.parse_cells(0)
        cell.update_signs(0)
      end
    end,
  })
  
  -- Auto-show inline output when cursor enters a cell
  vim.api.nvim_create_autocmd("CursorMoved", {
    pattern = "*.ipynb",
    callback = function()
      if not vim.b.jupyter_notebook then return end
      
      local bufnr = vim.api.nvim_get_current_buf()
      local current_cell = cell.get_current_cell(bufnr)
      
      -- Hide all inline outputs first
      output.hide_all_inline(bufnr)
      
      -- Show inline output for current cell if it exists
      if current_cell then
        output.show_inline(bufnr, current_cell)
      end
    end,
  })
end

return M
