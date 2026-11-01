local _, ns = ...

-- Minimap launcher (LibDataBroker + LibDBIcon) with a warband summary tooltip.
local Minimap = {}
ns.Minimap = Minimap

local NAME = "Lockout"
local ICON = "Interface\\AddOns\\Lockout\\Media\\Icon" -- Media/Icon.tga, drawn from Media/Icon.svg

-- Pure: how many characters have a vault ready, and the highest owned keystone.
-- Respects the same minimum-level filter as the main window.
function Minimap.Summary(db, now)
  local rows = ns.Rows.Build(db, {
    minLevel = db.settings and db.settings.minLevel, sortKey = "name",
  })
  local ready, bestKey = 0, nil
  for _, row in ipairs(rows) do
    if ns.Reset.Vault(row.char.vault, now).ready then ready = ready + 1 end
    local key = ns.Reset.MythicPlus(row.char.mythicPlus, now).key
    if key and key.level and (not bestKey or key.level > bestKey.level) then
      bestKey = { level = key.level, challengeMapID = key.challengeMapID, label = row.label }
    end
  end
  return { ready = ready, bestKey = bestKey }
end

local function dungeonName(challengeMapID)
  local ok, season = pcall(ns.Season.Get, ns.Season)
  if not ok or not season then return nil end
  for _, m in ipairs(season.mplus or {}) do
    if m.challengeMapID == challengeMapID then return m.name end
  end
end

function Minimap.FillTooltip(tt)
  tt:AddLine("Lockout")
  local summary = Minimap.Summary(ns.db, time())
  tt:AddLine(string.format("Vault ready: %d characters", summary.ready))
  local key = summary.bestKey
  if key then
    local name = dungeonName(key.challengeMapID)
    tt:AddLine(string.format("Highest key: +%d %s(%s)", key.level, name and (name .. " ") or "", key.label))
  end
end

-- Show or hide the button according to the saved setting.
function Minimap.Apply()
  local icon = Minimap.icon
  if not icon then return end
  if ns.db.settings.minimap.hide then icon:Hide(NAME) else icon:Show(NAME) end
end

local function onClick(_, button)
  if button == "RightButton" then
    if ns.Settings then ns.Settings:Open() end
  else
    ns.UI:Toggle()
  end
end

ns.On("DB_READY", function()
  local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not ldb or not icon then
    ns.Log("minimap libs missing")
    return
  end
  local obj = ldb:NewDataObject(NAME, {
    type = "launcher",
    icon = ICON,
    OnClick = onClick,
    OnTooltipShow = Minimap.FillTooltip,
  })
  icon:Register(NAME, obj, ns.db.settings.minimap)
  Minimap.icon = icon
end)
