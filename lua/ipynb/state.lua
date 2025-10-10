local M = {
  kernels = {},      -- bufnr -> kernel instance
  cells = {},        -- bufnr -> list of cells
  outputs = {},      -- bufnr -> cell_id -> output info
  cell_outputs = {}, -- bufnr -> cell_id -> saved output lines
}

return M
