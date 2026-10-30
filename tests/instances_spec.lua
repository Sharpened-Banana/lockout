local mock = require("tests.wow_mock")
local loader = require("tests.loader")

local function loadAddon(files, install)
  local list = { "Core/Init.lua", "Core/Util.lua", "Core/DB.lua", "Core/Reset.lua", "Data/Content.lua" }
  for _, f in ipairs(files) do list[#list + 1] = f end
  local ns = loader.load(list, install)
  ns.DB:Init(nil)
  return ns
end

describe("Instances collector", function()
  local saved, encounters, requested

  -- saved[i] = { name, reset, difficultyID, locked, extended, isRaid, difficultyName, numEncounters, progress, mapID }
  local function stubs()
    saved, encounters, requested = {}, {}, 0
    GetNumSavedInstances = function() return #saved end
    GetSavedInstanceInfo = function(i)
      local s = saved[i]
      return s.name, 1000 + i, s.reset, s.difficultyID, s.locked, s.extended, 0, s.isRaid,
        s.isRaid and 20 or 5, s.difficultyName, s.numEncounters, s.progress, false, s.mapID
    end
    GetSavedInstanceEncounterInfo = function(i, e)
      local list = encounters[i]
      local boss = list and list[e]
      if boss then return boss[1], 0, boss[2] end
    end
    RequestRaidInfo = function() requested = requested + 1 end
  end

  local function setup()
    local ns = loadAddon({ "Collectors/Instances.lua" }, stubs)
    return ns, ns.collectors.Instances, ns.DB:Current()
  end

  local function raid(mapID, locked, extended)
    return {
      name = "Raid " .. mapID, reset = 3600, difficultyID = 16, locked = locked, extended = extended,
      isRaid = true, difficultyName = "Mythic", numEncounters = 2, progress = 1, mapID = mapID,
    }
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "UPDATE_INSTANCE_INFO", "BOSS_KILL", "ENCOUNTER_END" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("requests raid info on login", function()
    local _, def = setup()
    def.OnLogin()
    assert.equals(1, requested)
  end)

  it("stores locked raid with encounters", function()
    local _, def, rec = setup()
    saved[1] = raid(2657, true, false)
    saved[2] = raid(2769, false, false)
    encounters[1] = { { "Boss1", true }, { "Boss2", false } }
    def:Collect(rec, mock.now)
    assert.is_nil(rec.instances["2769:16"])
    assert.same({
      ["2657:16"] = {
        name = "Raid 2657", mapID = 2657, difficultyID = 16, difficultyName = "Mythic", isRaid = true,
        resetAt = mock.now + 3600, extended = false, killed = 1, total = 2,
        encounters = { { name = "Boss1", killed = true }, { name = "Boss2", killed = false } },
      },
    }, rec.instances)
  end)

  it("extended unlocked kept", function()
    local _, def, rec = setup()
    saved[1] = raid(2657, false, true)
    def:Collect(rec, mock.now)
    assert.truthy(rec.instances["2657:16"])
    assert.is_true(rec.instances["2657:16"].extended)
  end)

  it("rebuild drops stale", function()
    local _, def, rec = setup()
    rec.instances["1:14"] = { name = "Old" }
    saved[1] = raid(2657, true, false)
    def:Collect(rec, mock.now)
    assert.is_nil(rec.instances["1:14"])
    assert.truthy(rec.instances["2657:16"])
  end)

  it("boss kill requests raid info", function()
    local ns, def = setup()
    def.OnEvent("BOSS_KILL", 1234)
    assert.equals(1, requested)
    def.OnEvent("ENCOUNTER_END", 1234)
    assert.equals(2, requested)
    def.OnEvent("UPDATE_INSTANCE_INFO")
    assert.equals(2, requested)
    mock.fire("BOSS_KILL", 1234)
    assert.equals(3, requested)
    assert.equals(0, #ns.log)
  end)

  it("runs through the bus", function()
    local ns, _, rec = setup()
    saved[1] = raid(2657, true, false)
    ns.CollectNow("Instances")
    assert.equals(0, #ns.log)
    assert.truthy(rec.instances["2657:16"])
  end)
end)

describe("WorldBosses collector", function()
  local completed, savedBosses

  local function stubs()
    completed, savedBosses = {}, nil
    C_QuestLog = { IsQuestFlaggedCompleted = function(id) return completed[id] == true end }
    C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 7200 end }
  end

  local function installSaved()
    GetNumSavedWorldBosses = function() return #savedBosses end
    GetSavedWorldBossInfo = function(i)
      local b = savedBosses[i]
      return b.name, b.id, b.reset
    end
  end

  local function setup(install)
    local ns = loadAddon({ "Collectors/WorldBosses.lua" }, function()
      stubs()
      if install then install() end
    end)
    return ns, ns.collectors.WorldBosses, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "UPDATE_INSTANCE_INFO", "QUEST_TURNED_IN" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("quest world boss uses weekly reset", function()
    local ns, def, rec = setup()
    ns.Content.WORLD_BOSSES = {
      { key = "q111", questID = 111, name = "Boss A" },
      { key = "q222", questID = 222, name = "Boss B" },
    }
    completed[111] = true
    def:Collect(rec, mock.now)
    assert.same({ q111 = { name = "Boss A", resetAt = mock.now + 7200 } }, rec.worldBosses)
  end)

  it("saved world boss api", function()
    local _, def, rec = setup(installSaved)
    savedBosses = { { name = "Saved Boss", id = 77, reset = 5000 } }
    def:Collect(rec, mock.now)
    assert.same({ wb77 = { name = "Saved Boss", resetAt = mock.now + 5000 } }, rec.worldBosses)
  end)

  it("works with empty WORLD_BOSSES", function()
    local ns, def, rec = setup()
    assert.same({}, ns.Content.WORLD_BOSSES)
    rec.worldBosses.old = { name = "Stale", resetAt = 1 }
    def:Collect(rec, mock.now)
    assert.same({}, rec.worldBosses)
  end)

  it("rebuilds from scratch each time", function()
    local ns, def, rec = setup(installSaved)
    ns.Content.WORLD_BOSSES = { { key = "q111", questID = 111, name = "Boss A" } }
    savedBosses = { { name = "Saved Boss", id = 77, reset = 5000 } }
    completed[111] = true
    def:Collect(rec, mock.now)
    assert.truthy(rec.worldBosses.q111)
    assert.truthy(rec.worldBosses.wb77)
    completed[111], savedBosses = nil, {}
    def:Collect(rec, mock.now)
    assert.same({}, rec.worldBosses)
  end)
end)
