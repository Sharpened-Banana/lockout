-- Loads addon files into a fresh namespace under the WoW mock.
local mock = require("tests.wow_mock")

local loader = {}

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Planned files only; ones not yet written by later tasks are skipped.
local function existing(list)
  local out = {}
  for _, path in ipairs(list) do
    if exists(path) then out[#out + 1] = path end
  end
  return out
end

loader.CORE = existing({
  "Core/Init.lua", "Core/Util.lua", "Core/DB.lua", "Core/Reset.lua", "Core/Watchlist.lua",
  "Data/Consumables.lua", "Data/Content.lua",
})

loader.ALL = existing({
  "Core/Init.lua", "Core/Util.lua", "Core/DB.lua", "Core/Reset.lua", "Core/Watchlist.lua",
  "Data/Consumables.lua", "Data/Content.lua", "Core/Season.lua",
  "Collectors/Character.lua", "Collectors/Equipment.lua", "Collectors/Instances.lua",
  "Collectors/WorldBosses.lua", "Collectors/Vault.lua", "Collectors/MythicPlus.lua",
  "Collectors/Delves.lua", "Collectors/Bags.lua", "Collectors/Holidays.lua",
  "UI/Theme.lua", "UI/Rows.lua",
  "UI/Tabs/Raids.lua", "UI/Tabs/Dungeons.lua", "UI/Tabs/WorldBosses.lua", "UI/Tabs/Weekly.lua", "UI/Tabs/Legacy.lua",
  "UI/Grid.lua", "UI/DetailPanel.lua", "UI/MainFrame.lua", "UI/Minimap.lua", "UI/Settings.lua",
})

-- load(files?, install?, addonName?) -> ns. An explicit list must exist on disk; the default is
-- loader.ALL. `install` runs after the reset and before any file loads, so API stubs are visible
-- to load-time checks such as a collector's `requires`. `addonName` (default "Lockout") is the
-- first vararg each file receives, as the client passes the addon's folder name.
function loader.load(files, install, addonName)
  mock.reset()
  if install then install() end
  local ns = {}
  for _, path in ipairs(files or loader.ALL) do
    local chunk, err = loadfile(path)
    if not chunk then error("loader: cannot load " .. path .. ": " .. tostring(err), 2) end
    chunk(addonName or "Lockout", ns)
  end
  return ns
end

return loader
