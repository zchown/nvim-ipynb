local M = {
  kernels = {},      -- bufnr -> kernel instance
  cells = {},        -- bufnr -> list of cells (sorted)
  outputs = {},      -- bufnr -> cell_id -> float output info
  cell_outputs = {}, -- bufnr -> cell_id -> saved output lines

  ns_cells = nil,
  ns_inline = nil,
  last_inline_cell = {},

  config = {
    default_kernel = "python3",
  },
}

return M

