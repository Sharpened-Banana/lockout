local mock = require("tests.wow_mock")
local loader = require("tests.loader")

local function loadAddon(files, install)
  local list = { "Core/Init.lua", "Core/Util.lua", "Core/DB.lua", "Core/Reset.lua", "Data/Content.lua" }
  for _, f in ipairs(files) do list[#list + 1] = f end
  local ns = loader.load(list, install)
  ns.DB:Init(nil)
  return ns
end

local T = Enum.WeeklyRewardChestThresholdType

describe("Vault collector", function()
  local activities, available, examples, ilvls

  local function stubs()
    activities, available, examples, ilvls = {}, false, {}, {}
    C_WeeklyRewards = {
      GetActivities = function() return activities end,
      HasAvailableRewards = function() return available end,
      GetExampleRewardItemHyperlinks = function(id) return examples[id] end,
    }
    C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 7200 end }
    C_Item = { GetDetailedItemLevelInfo = function(l) return ilvls[l] end }
  end

  local function setup()
    local ns = loadAddon({ "Collectors/Vault.lua" }, stubs)
    return ns, ns.collectors.Vault, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "WEEKLY_REWARDS_UPDATE" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("vault keeps raid/activities/world only", function()
    local _, def, rec = setup()
    activities = {
      { type = T.World, index = 1, threshold = 2, progress = 0, level = 0, id = 6 },
      { type = T.RankedPvP, index = 1, threshold = 1250, progress = 0, level = 0, id = 4 },
      { type = T.Raid, index = 2, threshold = 4, progress = 1, level = 15, id = 2 },
      { type = T.Activities, index = 1, threshold = 1, progress = 0, level = 0, id = 3 },
      { type = T.Raid, index = 1, threshold = 2, progress = 1, level = 15, id = 1 },
    }
    available = true
    def:Collect(rec, mock.now)
    assert.equals(mock.now + 7200, rec.vault.resetAt)
    assert.is_true(rec.vault.unclaimed)
    local order = {}
    for i, a in ipairs(rec.vault.activities) do order[i] = a.type .. ":" .. a.index end
    assert.same({ T.Activities .. ":1", T.Raid .. ":1", T.Raid .. ":2", T.World .. ":1" }, order)
    assert.same({ type = T.Raid, index = 1, threshold = 2, progress = 1, level = 15 }, rec.vault.activities[2])
  end)

  it("reward ilvl only for completed", function()
    local _, def, rec = setup()
    activities = {
      { type = T.Raid, index = 1, threshold = 2, progress = 2, level = 15, id = 1 },
      { type = T.Raid, index = 2, threshold = 4, progress = 3, level = 15, id = 2 },
      { type = T.Raid, index = 3, threshold = 6, progress = 6, level = 15, id = 3 },
    }
    examples[1], examples[2], examples[3] = "link1", "link2", nil
    ilvls.link1, ilvls.link2 = 678, 690
    def:Collect(rec, mock.now)
    assert.equals(678, rec.vault.activities[1].rewardIlvl)
    assert.is_nil(rec.vault.activities[2].rewardIlvl) -- not completed
    assert.is_nil(rec.vault.activities[3].rewardIlvl) -- no example link: nil-safe
  end)

  it("claimed vault clears ready", function()
    local ns, def, rec = setup()
    rec.vault = {
      resetAt = mock.now - 10, unclaimed = false,
      activities = { { type = T.Raid, index = 1, threshold = 2, progress = 2, level = 15 } },
    }
    assert.is_true(ns.Reset.Vault(rec.vault, mock.now).ready)
    available = false
    activities = { { type = T.Raid, index = 1, threshold = 2, progress = 0, level = 0, id = 1 } }
    def:Collect(rec, mock.now)
    assert.is_false(ns.Reset.Vault(rec.vault, mock.now).ready)
  end)

  it("handles no activities", function()
    local _, def, rec = setup()
    activities = nil
    def:Collect(rec, mock.now)
    assert.same({}, rec.vault.activities)
  end)
end)

describe("MythicPlus collector", function()
  local keyMap, keyLevel, history, summary

  local function stubs()
    keyMap, keyLevel, history, summary = nil, nil, {}, nil
    C_MythicPlus = {
      GetOwnedKeystoneChallengeMapID = function() return keyMap end,
      GetOwnedKeystoneLevel = function() return keyLevel end,
      GetRunHistory = function(includePrevious, includeIncomplete)
        assert.is_false(includePrevious)
        assert.is_true(includeIncomplete)
        return history
      end,
    }
    C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function(unit)
      assert.equals("player", unit)
      return summary
    end }
    C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 7200 end }
  end

  local function setup()
    local ns = loadAddon({ "Collectors/MythicPlus.lua" }, stubs)
    return ns, ns.collectors.MythicPlus, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({
      "CHALLENGE_MODE_COMPLETED", "BAG_UPDATE_DELAYED", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE",
    }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("mythic plus key and weekly best", function()
    local _, def, rec = setup()
    keyMap, keyLevel = 505, 10
    history = {
      { mapChallengeModeID = 505, level = 8, completed = true, thisWeek = true },
      { mapChallengeModeID = 506, level = 12, completed = false, thisWeek = true },
    }
    summary = {
      currentSeasonScore = 2450,
      runs = { { challengeModeID = 505, bestRunLevel = 11 }, { challengeModeID = 506, bestRunLevel = 9 } },
    }
    def:Collect(rec, mock.now)
    assert.same({
      resetAt = mock.now + 7200,
      key = { challengeMapID = 505, level = 10 },
      runs = {
        { challengeMapID = 505, level = 8, completed = true },
        { challengeMapID = 506, level = 12, completed = false },
      },
      weeklyBest = 12, -- the over-time +12 still counts toward the vault
      rating = 2450,
      seasonBest = { [505] = 11, [506] = 9 },
    }, rec.mythicPlus)
  end)

  it("weekly best counts over-time runs", function()
    local _, def, rec = setup()
    history = {
      { mapChallengeModeID = 505, level = 7, completed = true },
      { mapChallengeModeID = 506, level = 12, completed = false }, -- finished over time
      { mapChallengeModeID = 507, level = 9 },
    }
    def:Collect(rec, mock.now)
    assert.equals(12, rec.mythicPlus.weeklyBest)
    assert.equals(3, #rec.mythicPlus.runs)
  end)

  it("requests map info on login so run history is populated", function()
    local requested = 0
    local _, def = setup()
    C_MythicPlus.RequestMapInfo = function() requested = requested + 1 end
    def.OnLogin()
    assert.equals(1, requested)
    C_MythicPlus.RequestMapInfo = nil
    def.OnLogin() -- tolerates the API being absent
    assert.equals(1, requested)
  end)

  it("no key stores nil", function()
    local _, def, rec = setup()
    rec.mythicPlus = { key = { challengeMapID = 1, level = 2 } }
    def:Collect(rec, mock.now)
    assert.is_nil(rec.mythicPlus.key)
    assert.equals(0, rec.mythicPlus.weeklyBest)
    assert.same({}, rec.mythicPlus.runs)
  end)

  it("rating summary nil-safe", function()
    local _, def, rec = setup()
    summary = nil
    def:Collect(rec, mock.now)
    assert.equals(0, rec.mythicPlus.rating)
    assert.same({}, rec.mythicPlus.seasonBest)
  end)

  it("history nil-safe", function()
    local _, def, rec = setup()
    history = nil
    def:Collect(rec, mock.now)
    assert.same({}, rec.mythicPlus.runs)
    assert.equals(0, rec.mythicPlus.weeklyBest)
  end)
end)

describe("Delves collector", function()
  local infos

  local function stubs()
    infos = {}
    C_CurrencyInfo = { GetCurrencyInfo = function(id) return infos[id] end }
  end

  local function setup()
    local ns = loadAddon({ "Collectors/Delves.lua" }, stubs)
    return ns, ns.collectors.Delves, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "CURRENCY_DISPLAY_UPDATE" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("delves currencies", function()
    local ns, def, rec = setup()
    ns.Content.DELVE_CURRENCIES = {
      { id = 9001, name = "Key" }, { id = 9002, name = "Shard" }, { id = 9003, name = "Missing" },
    }
    infos[9001], infos[9002] = { quantity = 3 }, { quantity = 150 }
    def:Collect(rec, mock.now)
    assert.same({ updatedAt = mock.now, currencies = { [9001] = 3, [9002] = 150 } }, rec.delves)
  end)

  it("delves empty data", function()
    local ns, def, rec = setup()
    assert.same({}, ns.Content.DELVE_CURRENCIES)
    def:Collect(rec, mock.now)
    assert.same({ updatedAt = mock.now, currencies = {} }, rec.delves)
  end)

  it("runs through the bus", function()
    local ns, _, rec = setup()
    ns.CollectNow("Delves")
    assert.equals(0, #ns.log)
    assert.equals(mock.now, rec.delves.updatedAt)
  end)
end)

describe("Holidays collector", function()
  local dungeons, infos, rewards, requested

  local function stubs()
    dungeons, infos, rewards, requested = {}, {}, {}, 0
    GetNumRandomDungeons = function() return #dungeons end
    GetLFGRandomDungeonInfo = function(i) local d = dungeons[i]; return d.id, d.name end
    -- isHoliday is the 15th return
    GetLFGDungeonInfo = function(id)
      local h = infos[id]
      if not h then return nil end
      return h.name, 1, 0, 0, 0, 0, 0, 0, 0, 0, "", 0, 5, "", h.holiday
    end
    GetLFGDungeonRewards = function(id) return rewards[id] == true end
    RequestLFDPlayerLockInfo = function() requested = requested + 1 end
    C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
  end

  local function setup(install)
    local ns = loadAddon({ "Collectors/Holidays.lua" }, function()
      stubs()
      if install then install() end
    end)
    return ns, ns.collectors.Holidays, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "LFG_UPDATE_RANDOM_INFO", "LFG_COMPLETION_REWARD" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("requests dungeon info on login and after a reward", function()
    local _, def = setup()
    def.OnLogin()
    assert.equals(1, requested)
    def.OnEvent("LFG_COMPLETION_REWARD")
    assert.equals(2, requested)
    def.OnEvent("LFG_UPDATE_RANDOM_INFO")
    assert.equals(2, requested)
  end)

  it("holiday dungeons are active, done when rewarded, others skipped", function()
    local _, def, rec = setup()
    dungeons = { { id = 285, name = "Headless Horseman" }, { id = 286, name = "Ahune" }, { id = 9, name = "Random Dungeon" } }
    infos[285], infos[286], infos[9] = { holiday = true }, { holiday = true }, { holiday = false }
    rewards[285] = true
    def:Collect(rec, mock.now)
    assert.same({
      active = {
        [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 },
        [286] = { name = "Ahune", resetAt = mock.now + 3600 },
      },
      done = { [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 } },
    }, rec.holidays)
  end)

  it("falls back to the dungeon info name", function()
    local _, def, rec = setup()
    dungeons = { { id = 287 } }
    infos[287] = { name = "Coren Direbrew", holiday = true }
    def:Collect(rec, mock.now)
    assert.equals("Coren Direbrew", rec.holidays.active[287].name)
  end)

  it("empty list writes empty tables and drops stale entries", function()
    local _, def, rec = setup()
    rec.holidays = { active = { [1] = { name = "Old" } }, done = {} }
    def:Collect(rec, mock.now)
    assert.same({ active = {}, done = {} }, rec.holidays)
  end)

  it("a dungeon without info is skipped", function()
    local _, def, rec = setup()
    dungeons = { { id = 400, name = "Loading" }, { id = 285, name = "Headless Horseman" } }
    infos[285] = { holiday = true }
    def:Collect(rec, mock.now)
    assert.same({ [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 } }, rec.holidays.active)
  end)

  it("unknown daily reset leaves resetAt nil", function()
    local _, def, rec = setup(function()
      C_DateAndTime.GetSecondsUntilDailyReset = function() return nil end
    end)
    dungeons = { { id = 285, name = "Headless Horseman" } }
    infos[285] = { holiday = true }
    def:Collect(rec, mock.now)
    assert.is_nil(rec.holidays.active[285].resetAt)
    assert.equals("Headless Horseman", rec.holidays.active[285].name)
  end)

  it("disables itself without the rewards API", function()
    local _, def = setup(function() GetLFGDungeonRewards = nil end)
    assert.is_true(def.disabled)
  end)
end)
