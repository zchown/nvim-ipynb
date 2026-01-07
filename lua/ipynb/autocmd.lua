local cell = require('ipynb.cell')
local notebook = require('ipynb.notebook')
local output = require('ipynb.output')
local state = require('ipynb.state')

local M = {}

local function debounce(ms, fn)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(ms, 0, function()
      timer:stop()
      timer:close()
      timer = nil
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

local function update_cells_and_signs(bufnr)
  cell.parse_cells(bufnr)
  cell.update_signs(bufnr)
end

local debounced_update = debounce(120, update_cells_and_signs)

function M.setup()
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "*.ipynb",
    callback = function(args)
      local notebook_path = vim.fn.fnamemodify(args.file, ":p")
      local detected = notebook.detect_kernel(notebook_path)
      if detected then
          vim.b.ipynb_kernel = detected
      end
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
        update_cells_and_signs(0)
      end, 50)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = "*.ipynb",
    callback = function()
      notebook.save(0, vim.b.jupyter_notebook)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    pattern = "*.ipynb",
    callback = function(args)
      if vim.b.jupyter_notebook then
        debounced_update(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorHold", {
    pattern = "*.ipynb",
    callback = function(args)
      if not vim.b.jupyter_notebook then return end
      local bufnr = args.buf

      local current_cell = cell.get_current_cell(bufnr)
      if not current_cell then
        output.hide_all_inline(bufnr)
        return
      end

      if state.last_inline_cell[bufnr] ~= current_cell.id then
        output.show_inline(bufnr, current_cell)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    pattern = "*.ipynb",
    callback = function(args)
      local bufnr = args.buf
      output.hide_all_inline(bufnr)
      state.cells[bufnr] = nil
      state.outputs[bufnr] = nil
      state.cell_outputs[bufnr] = nil
      state.last_inline_cell[bufnr] = nil
    end,
  })
end

return M

