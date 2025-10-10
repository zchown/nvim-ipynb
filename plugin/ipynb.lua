if vim.g.loaded_ipynb then
  return
end
vim.g.loaded_ipynb = 1

local jupyter = require('ipynb')

-- Initialize the plugin
jupyter.setup()

-- Create user commands
vim.api.nvim_create_user_command("JupyterRunCell", function()
  jupyter.run_cell()
end, {})

vim.api.nvim_create_user_command("JupyterRunAll", function()
  jupyter.run_all_cells()
end, {})

vim.api.nvim_create_user_command("JupyterToggleOutput", function()
  jupyter.toggle_output()
end, {})

vim.api.nvim_create_user_command("JupyterCloseOutput", function()
  jupyter.close_output()
end, {})

vim.api.nvim_create_user_command("JupyterNextCell", function()
  jupyter.next_cell()
end, {})

vim.api.nvim_create_user_command("JupyterPrevCell", function()
  jupyter.prev_cell()
end, {})

vim.api.nvim_create_user_command("JupyterStartKernel", function()
  jupyter.start_kernel()
end, {})

vim.api.nvim_create_user_command("JupyterStopKernel", function()
  jupyter.stop_kernel()
end, {})

vim.api.nvim_create_user_command("JupyterRestartKernel", function()
  jupyter.restart_kernel()
end, {})
