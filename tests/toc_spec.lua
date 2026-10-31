local loader = require("tests.loader")

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Non-comment, non-blank TOC lines with WoW's backslashes turned into slashes.
local function tocFiles()
  local out = {}
  for line in io.lines("Lockout.toc") do
    line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then out[#out + 1] = (line:gsub("\\", "/")) end
  end
  return out
end

describe("Lockout.toc", function()
  it("lists every file on disk", function()
    local files = tocFiles()
    assert.truthy(#files > 0)
    for _, path in ipairs(files) do
      assert(exists(path), "TOC entry missing on disk: " .. path)
    end
  end)

  it("loads the same Lua files, in the same order, as the test loader", function()
    local lua = {}
    for _, path in ipairs(tocFiles()) do
      if path:find("%.lua$") then lua[#lua + 1] = path end
    end
    assert.same(loader.ALL, lua)
  end)
end)
