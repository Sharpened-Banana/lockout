-- Minimal busted-style runner: lua5.1 tests/run.lua [spec files...]
package.path = "./?.lua;./?/init.lua;" .. package.path

local write = io.write
local tests, current = {}, nil

local function fullName(node, leaf)
  local parts = { leaf }
  while node and node.name do
    table.insert(parts, 1, node.name)
    node = node.parent
  end
  return table.concat(parts, " > ")
end

function describe(name, fn)
  local node = { name = name, parent = current, hooks = {} }
  local prev = current
  current = node
  fn()
  current = prev
end

function it(name, fn)
  tests[#tests + 1] = { name = name, node = current, fn = fn }
end

function before_each(fn)
  if not current then error("before_each outside describe", 2) end
  table.insert(current.hooks, fn)
end

local function show(v, seen)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = "[" .. show(k, seen) .. "]=" .. show(v[k], seen)
  end
  seen[v] = nil
  return "{" .. table.concat(out, ", ") .. "}"
end

local function deepEqual(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not deepEqual(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function fail(msg) error(msg, 3) end

local A = {}
function A.equals(expected, actual)
  if expected ~= actual then
    fail("expected " .. show(expected) .. ", got " .. show(actual))
  end
end
function A.same(expected, actual)
  if not deepEqual(expected, actual) then
    fail("expected " .. show(expected) .. ", got " .. show(actual))
  end
end
function A.is_true(v) if v ~= true then fail("expected true, got " .. show(v)) end end
function A.is_false(v) if v ~= false then fail("expected false, got " .. show(v)) end end
function A.is_nil(v) if v ~= nil then fail("expected nil, got " .. show(v)) end end
function A.truthy(v) if not v then fail("expected truthy value, got " .. show(v)) end end
function A.has_error(fn)
  if pcall(fn) then fail("expected function to raise an error") end
end
assert = setmetatable(A, {
  __call = function(_, v, msg)
    if not v then error(msg or "assertion failed!", 2) end
    return v
  end,
})

local files = {}
for _, a in ipairs(arg or {}) do files[#files + 1] = a end
if #files == 0 then
  local p = io.popen("ls tests/*_spec.lua")
  for line in p:lines() do files[#files + 1] = line end
  p:close()
end

local passed, failed = 0, 0
local failures = {}

for _, path in ipairs(files) do
  local chunk, err = loadfile(path)
  if not chunk then
    failed = failed + 1
    failures[#failures + 1] = path .. ": " .. tostring(err)
  else
    current = nil
    local ok, e = pcall(chunk)
    if not ok then
      failed = failed + 1
      failures[#failures + 1] = path .. ": " .. tostring(e)
    end
  end
end

for _, t in ipairs(tests) do
  local chain, n = {}, t.node
  while n do table.insert(chain, 1, n); n = n.parent end
  local ok, e = pcall(function()
    for _, node in ipairs(chain) do
      for _, h in ipairs(node.hooks) do h() end
    end
    t.fn()
  end)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = fullName(t.node, t.name) .. ": " .. tostring(e)
  end
end

for _, f in ipairs(failures) do write("FAIL ", f, "\n") end
write(passed, " passed, ", failed, " failed\n")
os.exit(failed > 0 and 1 or 0)
