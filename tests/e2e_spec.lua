local loader = require("tests.loader")
local mock = require("tests.wow_mock")

-- End to end: every addon file, saved-variable shapes from the wild, the client's event
-- order, then every tab and the detail panel. Nothing may raise or log a failure.

local HELM_LINK = "|cffa335ee|Hitem:1001::::::::80:::::|h[Helm]|h|r"

local function install()
  UIParent = CreateFrame("Frame", "UIParent")
  GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
  C_ClassColor = { GetClassColor = function() end }
  IsShiftKeyDown = function() return false end
  -- Season
  GetBuildInfo = function() return "12.0.7", "66666", "Oct 1 2026", 120007 end
  LE_EXPANSION_LEVEL_CURRENT = 11
  EXPANSION_NAME11 = "Midnight"
  EJ_GetNumTiers = function() return 1 end
  EJ_GetTierInfo = function() return "Midnight" end
  EJ_GetCurrentTier = function() return 1 end
  EJ_SelectTier = function() end
  EJ_GetInstanceByIndex = function(i, isRaid)
    if i == 1 then return isRaid and 100 or 200, isRaid and "Raid A" or "Dun A" end
  end
  EJ_GetInstanceInfo = function(id) return "", "", "", "", "", "", 0, "", false, id + 2000 end
  EJ_GetEncounterInfoByIndex = function(j) if j <= 2 then return "Boss" .. j end end
  C_ChallengeMode = {
    GetMapTable = function() return { 501 } end,
    GetMapUIInfo = function(id) if id == 501 then return "Dun A", 501, 1800, 1, 2, 2200 end end,
  }
  -- Character / Equipment
  GetAverageItemLevel = function() return 640.5, 638.2 end
  GetSpecialization = function() return 1 end
  GetSpecializationInfo = function() return 262 end
  GetMoney = function() return 123456 end
  GetInventoryItemLink = function(_, slot) if slot == 1 then return HELM_LINK end end
  C_TooltipInfo = { GetInventoryItem = function() return { lines = { { leftText = "Upgrade Level: Hero 4/6" } } } end }
  C_Item = {
    GetDetailedItemLevelInfo = function() return 645 end,
    GetItemInfoInstant = function(id) return id, "Armor", "Plate", "INVTYPE_HEAD" end,
    GetItemStats = function() return { EMPTY_SOCKET_PRISMATIC = 1 } end,
    GetItemIconByID = function() return 134400 end,
    GetItemNameByID = function() end,
  }
  -- Instances / world bosses
  GetNumSavedInstances = function() return 1 end
  GetSavedInstanceInfo = function()
    return "Raid A", 1, 3600, 15, true, false, false, true, 20, "Heroic", 2, 1, false, 2100
  end
  GetSavedInstanceEncounterInfo = function(_, e) return "Boss" .. e, nil, e == 1 end
  RequestRaidInfo = function() end
  GetNumSavedWorldBosses = function() return 0 end
  C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
  C_DateAndTime = {
    GetSecondsUntilWeeklyReset = function() return 86400 end,
    GetSecondsUntilDailyReset = function() return 3600 end,
  }
  -- Dungeon finder (Holidays)
  GetNumRandomDungeons = function() return 0 end
  GetLFGRandomDungeonInfo = function() end
  GetLFGDungeonInfo = function() end
  IsLFGDungeonJoinable = function() return true, true, false end
  GetLFGDungeonRewards = function() return false end
  RequestLFDPlayerLockInfo = function() end
  -- Vault / M+ / delves / bags
  C_WeeklyRewards = {
    GetActivities = function()
      return { { type = 1, index = 1, threshold = 1, progress = 1, level = 10, id = 9 } }
    end,
    HasAvailableRewards = function() return false end,
  }
  C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return 501 end,
    GetOwnedKeystoneLevel = function() return 12 end,
    GetRunHistory = function() return { { mapChallengeModeID = 501, level = 11, completed = true } } end,
    RequestMapInfo = function() end,
  }
  C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function()
    return { currentSeasonScore = 2100, runs = { { challengeModeID = 501, bestRunLevel = 12 } } }
  end }
  C_CurrencyInfo = { GetCurrencyInfo = function() end }
  C_Container = {
    GetContainerNumSlots = function() return 2 end,
    GetContainerItemInfo = function() end,
  }
  -- Detail panel
  GetMoneyString = function(copper) return tostring(copper) end
  GetSpecializationInfoByID = function() end
  CLASS_ICON_TCOORDS = {}
  StaticPopupDialogs = {}
  StaticPopup_Show = function() end
end

local ALT = "Player-2-0002"

local SHAPES = {
  ["nil"] = function() return nil end,
  ["empty table"] = function() return {} end,
  ["meta-only records"] = function()
    return { characters = {
      [mock.player.guid] = { meta = { name = "Thrall" } },
      [ALT] = { meta = { name = "Alt" } },
    } }
  end,
  ["partial settings"] = function()
    return { schema = 1, settings = { scale = 0.8, minimap = {}, window = { width = 900 } },
      characters = { [ALT] = { meta = { name = "Alt", level = 80 } } } }
  end,
  ["malformed season"] = function()
    return { season = { build = "66666", raids = "x", dungeons = 3 } }
  end,
  ["season from another build"] = function()
    return { season = { build = 120007, raids = { { mapID = 1, name = "Old" } }, dungeons = {}, mplus = {} } }
  end,
}

local function failures(ns)
  local out = {}
  for _, line in ipairs(ns.log) do
    if line:find("failed", 1, true) or line:find("disabled", 1, true) then out[#out + 1] = line end
  end
  return out
end

describe("end to end", function()
  for label, shape in pairs(SHAPES) do
    it("runs a session from LockoutDB = " .. label, function()
      local ns = loader.load(nil, install, "Lockout")
      LockoutDB = shape() -- SavedVariables are set after the files run, before ADDON_LOADED
      mock.fire("ADDON_LOADED", "Lockout")
      assert.equals(LockoutDB, ns.db)
      mock.fire("PLAYER_LOGIN")
      mock.advance(5)
      mock.fire("UPDATE_INSTANCE_INFO")
      mock.fire("BAG_UPDATE_DELAYED")
      mock.advance(5)

      local current = ns.db.characters[mock.player.guid]
      assert.equals("Thrall", current.meta.name)
      assert.equals(645, current.equipment[1].ilvl)
      assert.truthy(current.instances["2100:15"])
      assert.same({}, current.legacyBosses)
      assert.same({ active = {}, done = {} }, current.holidays)

      SlashCmdList.LOCKOUT("")
      assert.is_true(LockoutMainFrame:IsShown())
      for name in pairs(ns.Tabs) do ns.UI:SelectTab(name) end
      for guid in pairs(ns.db.characters) do ns.Detail:Open(guid) end
      assert.is_true(ns.Detail.panel:IsVisible())
      ns.Fire("DATA_UPDATED", "Character")
      SlashCmdList.LOCKOUT("debug")

      assert.same({}, failures(ns))
    end)
  end
end)
