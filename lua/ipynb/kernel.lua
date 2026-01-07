local state = require('ipynb.state')

local M = {}

local Kernel = {}
Kernel.__index = Kernel

function Kernel.new(bufnr, kernel_type)
  return setmetatable({
    bufnr = bufnr,
    kernel_type = kernel_type or "python3",
    job_id = nil,
    running = false,

    queue = {},
    busy = false,
    current = nil,

    raw_buffer = "",
    token_counter = 0,
  }, Kernel)
end

function Kernel:start()
  if self.running then
    vim.notify("Kernel already running", vim.log.levels.WARN)
    return true
  end

  local cmd = {
    "jupyter",
    "console",
    "--kernel=" .. self.kernel_type,
    "--simple-prompt",
  }

  self.job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _) self:on_output(data) end,
    on_stderr = function(_, data, _) self:on_error(data) end,
    on_exit   = function(_, code, _) self:on_exit(code) end,
    pty = true,
  })

  if self.job_id <= 0 then
    vim.notify("Failed to start kernel", vim.log.levels.ERROR)
    return false
  end

  self.running = true
  state.kernels[self.bufnr] = self
  vim.notify("Kernel started (" .. self.kernel_type .. ")", vim.log.levels.INFO)
  return true
end

local function make_token(self)
  self.token_counter = self.token_counter + 1
  return string.format("__NVIM_IPYNB_SENTINEL_%d__", self.token_counter)
end

local function normalize_newlines(s)
  -- PTY output often uses \r\n or includes lone \r
  return (s or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function find_token_as_line(buf, token)
  -- Return the index in buf where the token-line starts (0-based-ish not needed),
  -- or nil if not found. This searches for token as a whole line, robustly.
  if not token or token == "" then return nil end

  -- token on its own line in the middle
  local needle_mid = "\n" .. token .. "\n"
  local s = buf:find(needle_mid, 1, true)
  if s then
    return s + 1 -- start of token within needle_mid
  end

  -- token at start followed by newline
  local needle_start = token .. "\n"
  local s2 = buf:find(needle_start, 1, true)
  if s2 == 1 then
    return 1
  end

  -- token at end preceded by newline (no trailing newline)
  local needle_end = "\n" .. token
  local s3 = buf:find(needle_end, 1, true)
  if s3 and (s3 + #needle_end - 1) == #buf then
    return s3 + 1
  end

  -- token is entire buffer (extremely rare)
  if buf == token then
    return 1
  end

  return nil
end

local function b64_encode(s)
  -- Prefer Neovim builtin if present
  if vim.base64 and vim.base64.encode then
    local ok, out = pcall(vim.base64.encode, s)
    if ok and type(out) == "string" then
      return out
    end
  end

  -- Fallback: system base64 (no shell quoting)
  local out = vim.fn.system({ "base64" }, s)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  -- base64 tool often adds a trailing newline
  return (out:gsub("%s+$", ""))
end

-- Build a python wrapper that always prints the sentinel, even on error.
local function build_payload(code, token)
  code = code or ""

  local code_b64 = b64_encode(code) or ""

  local script = table.concat({
    ("__NVIM_TOKEN = %q"):format(token),
    ("__NVIM_CODE_B64 = %q"):format(code_b64),
    [[
import base64, traceback, ast

try:
    __NVIM_CODE = base64.b64decode(__NVIM_CODE_B64).decode("utf-8")

    tree = ast.parse(__NVIM_CODE, mode="exec")

    __nv_last_value = None

    if tree.body and isinstance(tree.body[-1], ast.Expr):
        last_expr = tree.body[-1]
        tree.body[-1] = ast.Assign(
            targets=[ast.Name(id="__nv_last_value", ctx=ast.Store())],
            value=last_expr.value
        )
        ast.fix_missing_locations(tree)

    exec(compile(tree, "<ipynb-cell>", "exec"), globals())

    if "__nv_last_value" in globals() and __nv_last_value is not None:
        print(repr(__nv_last_value))

except Exception:
    traceback.print_exc()

finally:
    print(__NVIM_TOKEN)
]],
  }, "\n")

  local script_b64 = b64_encode(script) or ""

  return (
    'import base64; exec(base64.b64decode(%q).decode("utf-8"), globals())\n'
  ):format(script_b64)
end


function Kernel:execute(code, callback)
  if not self.running then
    vim.notify("Kernel not running", vim.log.levels.ERROR)
    return
  end

  local token = make_token(self)
  table.insert(self.queue, { code = code or "", callback = callback, token = token })
  self:maybe_start_next()
end

function Kernel:maybe_start_next()
  if self.busy or #self.queue == 0 or not self.running then return end

  self.busy = true
  self.current = table.remove(self.queue, 1)
  self.raw_buffer = ""

  -- Safety timeout so we don't get stuck forever if token isn't observed
  if self._timeout_timer then
    self._timeout_timer:stop()
    self._timeout_timer:close()
    self._timeout_timer = nil
  end

  self._timeout_timer = vim.loop.new_timer()
  self._timeout_timer:start(10000, 0, function()
    vim.schedule(function()
      if self.busy and self.current then
        local before = normalize_newlines(self.raw_buffer)
        -- Finish with whatever we got (better than deadlocking)
        self:finish_current(before)
      end
    end)
  end)

  local payload = build_payload(self.current.code, self.current.token)
  vim.fn.chansend(self.job_id, payload)
end


-- Strip ANSI, prompts, echoed input, and other console noise.
function Kernel:process_output(raw, token)
  local s = raw or ""

  -- Strip ANSI
  s = s:gsub("\27%[[0-9;]*m", "")

  -- Normalize newlines
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")

  local lines = vim.split(s, "\n", { plain = true })
  local cleaned = {}

  local function strip_prompt_prefix(line)
    -- simple-prompt (ipython console)
    line = line:gsub("^>>>%s?", "")
    line = line:gsub("^%.%.%.%s?", "")

    -- jupyter-console classic prompts
    line = line:gsub("^In %[%d+%]:%s*", "")
    line = line:gsub("^Out%[%d+%]:%s*", "")
    return line
  end

  for _, line in ipairs(lines) do
    -- Drop the sentinel if it appears
    if token and token ~= "" and line:find(token, 1, true) then
      goto continue
    end

    -- Remove prompt prefix, *then* match on the underlying content
    local unprompted = strip_prompt_prefix(line)

    -- Drop our injected one-liner echo
    -- (after prompt stripping it will begin with "import base64; exec(")
    if unprompted:match("^import%s+base64;%s*exec%(") then
      goto continue
    end

    -- Drop occasional console artifacts
    if unprompted == "NoneType: None" then
      goto continue
    end

    -- Normalize whitespace-only lines
    if unprompted:match("^%s*$") then
      if #cleaned > 0 and cleaned[#cleaned] ~= "" then
        table.insert(cleaned, "")
      end
      goto continue
    end

    table.insert(cleaned, unprompted)

    ::continue::
  end

  -- Trim trailing blanks
  while #cleaned > 0 and cleaned[#cleaned] == "" do
    table.remove(cleaned, #cleaned)
  end

  return cleaned
end

function Kernel:finish_current(before_token_text)
  local item = self.current
  self.current = nil
  self.busy = false

  if item and item.callback then
    local lines = self:process_output(before_token_text, item.token)
    item.callback(lines)
  end

  self:maybe_start_next()
end

function Kernel:on_output(data)
  if not data or #data == 0 then return end
  if not self.busy or not self.current then return end

  for _, chunk in ipairs(data) do
    if chunk and chunk ~= "" then
      self.raw_buffer = self.raw_buffer .. chunk
    end
  end

  local token = self.current.token
  local buf = normalize_newlines(self.raw_buffer)

  local pos = find_token_as_line(buf, token)
  if pos then
    -- everything before the token-line
    local before = buf:sub(1, pos - 1)
    before = before:gsub("\n*$", "\n")

    -- stop timeout timer
    if self._timeout_timer then
      self._timeout_timer:stop()
      self._timeout_timer:close()
      self._timeout_timer = nil
    end

    self:finish_current(before)
  end
end

function Kernel:on_error(data)
  if not data or #data == 0 then return end
  -- stderr can include non-fatal noise; keep as notify
  vim.notify("Kernel stderr:\n" .. table.concat(data, "\n"), vim.log.levels.WARN)
end

function Kernel:on_exit(code)
  self.running = false
  self.busy = false
  self.current = nil
  self.queue = {}
  state.kernels[self.bufnr] = nil
  vim.notify("Kernel exited (" .. tostring(code) .. ")", vim.log.levels.WARN)
end

function Kernel:stop()
  if self.running and self.job_id then
    vim.fn.jobstop(self.job_id)
  end
  self.running = false
  self.busy = false
  self.current = nil
  self.queue = {}
  state.kernels[self.bufnr] = nil
  vim.notify("Kernel stopped", vim.log.levels.INFO)
end

-- per-buffer kernel name helper (works with your per-notebook kernel plan)
local function get_buf_var(bufnr, name)
  local ok, v = pcall(vim.api.nvim_buf_get_var, bufnr, name)
  if ok then return v end
  return nil
end

local function resolve_kernel_name(bufnr)
  local bkernel = get_buf_var(bufnr, "ipynb_kernel")
  if type(bkernel) == "string" and bkernel ~= "" then
    return bkernel
  end
  if state.config and type(state.config.default_kernel) == "string" and state.config.default_kernel ~= "" then
    return state.config.default_kernel
  end
  return "python3"
end

function M.get_or_create(bufnr)
  local k = state.kernels[bufnr]
  local want = resolve_kernel_name(bufnr)

  if k and k.running and k.kernel_type ~= want then
    k:stop()
    k = nil
  end

  if not k or not k.running then
    k = Kernel.new(bufnr, want)
    if not k:start() then return nil end
  end

  return k
end

function M.start(bufnr)
  local k = Kernel.new(bufnr, resolve_kernel_name(bufnr))
  k:start()
end

function M.stop(bufnr)
  local k = state.kernels[bufnr]
  if k then k:stop() end
end

return M

