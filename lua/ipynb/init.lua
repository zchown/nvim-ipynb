local cell = require('ipynb.cell')
local kernel = require('ipynb.kernel')
local output = require('ipynb.output')
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
    if out and #out > 0 then
      output.display(bufnr, current_cell, out, false)
    end
  end)
end

function M.run_all_cells()
  local bufnr = vim.api.nvim_get_current_buf()
  local cells = cell.parse_cells(bufnr)
  if #cells == 0 then
    return vim.notify("No cells", vim.log.levels.WARN)
  end

  local k = kernel.get_or_create(bufnr)
  if not k then return end

  local i = 1
  local function run_next()
    if i > #cells then
      vim.notify("All cells done", vim.log.levels.INFO)
      return
    end

    local c = cells[i]
    vim.api.nvim_win_set_cursor(0, { c.start_line, 0 })

    k:execute(c:get_content(), function(out)
      if out and #out > 0 then
        output.display(bufnr, c, out, false)
      end
      i = i + 1
      run_next()
    end)
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
  vim.defer_fn(M.start_kernel, 300)
end

function M.setup(opts)
  opts = opts or {}

  local state = require('ipynb.state')
  state.config.default_kernel = opts.default_kernel or state.config.default_kernel or "python3"

  vim.api.nvim_set_hl(0, "JupyterCell", { fg = "#61AFEF", bold = true })
  vim.api.nvim_set_hl(0, "JupyterInlineOutput", { bg = "#264f78" })

  vim.fn.sign_define("jupyter_cell", {
    text = "▎",
    texthl = "JupyterCell",
    linehl = "CursorLine",
  })

  require('ipynb.autocmd').setup()

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

  vim.api.nvim_create_user_command("IpynbKernel", function(cmdopts)
    if cmdopts.args == "" then
      local cur = vim.b.ipynb_kernel or state.config.default_kernel or "python3"
      vim.notify("Notebook kernel: " .. cur, vim.log.levels.INFO)
      return
    end

    vim.b.ipynb_kernel = cmdopts.args
    vim.notify("Set notebook kernel to: " .. cmdopts.args .. " (restarting)", vim.log.levels.INFO)

    M.restart_kernel()
  end, {
    nargs = "?",
    complete = function()
      local out = vim.fn.system({ "jupyter", "kernelspec", "list", "--json" })
      if vim.v.shell_error ~= 0 then return {} end
      local ok, obj = pcall(vim.json.decode, out)
      if not ok or type(obj) ~= "table" or type(obj.kernelspecs) ~= "table" then return {} end
      local items = {}
      for name, _ in pairs(obj.kernelspecs) do
        table.insert(items, name)
      end
      table.sort(items)
      return items
    end,
  })

  vim.api.nvim_create_user_command("IpynbKernels", function()
    local out = vim.fn.system({ "jupyter", "kernelspec", "list" })
    if vim.v.shell_error ~= 0 then
      vim.notify("Failed to list kernels (is jupyter installed?)", vim.log.levels.ERROR)
      return
    end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(out, "\n", { plain = true }))
    vim.bo[b].bufhidden = "wipe"
    vim.bo[b].filetype = "text"
    vim.api.nvim_open_win(b, true, {
      relative = "editor",
      width = math.floor(vim.o.columns * 0.7),
      height = math.floor(vim.o.lines * 0.6),
      row = math.floor(vim.o.lines * 0.2),
      col = math.floor(vim.o.columns * 0.15),
      border = "rounded",
      title = " Jupyter kernelspec list ",
      title_pos = "center",
    })
  end, {})

end

return M

