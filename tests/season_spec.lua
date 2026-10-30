local mock = require("tests.wow_mock")
local loader = require("tests.loader")

describe("Content", function()
  it("slot order and names fall back to English", function()
    local ns = loader.load({ "Data/Content.lua" })
    assert.same({ 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }, ns.Content.EQUIP_SLOTS)
    for _, slot in ipairs(ns.Content.EQUIP_SLOTS) do
      assert.equals("string", type(ns.Content.SLOT_NAMES[slot]))
    end
    assert.equals("Head", ns.Content.SLOT_NAMES[1])
    assert.equals("Off Hand", ns.Content.SLOT_NAMES[17])
  end)

  it("uses Blizzard slot globals when present", function()
    mock.reset()
    HEADSLOT = "Kopf"
    local ns = {}
    loadfile("Data/Content.lua")("Lockout", ns) -- loader.load would reset the stub away
    assert.equals("Kopf", ns.Content.SLOT_NAMES[1])
  end)

  it("marks enchantable slots and tolerates empty ID tables", function()
    local ns = loader.load({ "Data/Content.lua" })
    local expect = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true, [11] = true, [12] = true, [16] = true }
    assert.same(expect, ns.Content.ENCHANT_SLOTS)
    assert.same({}, ns.Content.WORLD_BOSSES)
    assert.same({}, ns.Content.DELVE_CURRENCIES)
  end)
end)

describe("Season", function()
  local ns, calls, selected, build

  local function stubEJ()
    calls = { ej = 0, select = {} }
    selected = 1
    build = 120007
    local function count() calls.ej = calls.ej + 1 end
    local tiers = { "Classic", "Midnight" }
    local raids = { { 100, "Raid A", 2100, 3 }, { 101, "Midnight", 2101, 1 } }
    local dungeons = { { 200, "Dun A", 2001, 0 } }
    local function list(kind) return kind and raids or dungeons end
    local info = {}
    for _, l in ipairs({ raids, dungeons }) do
      for _, e in ipairs(l) do info[e[1]] = e end
    end

    EXPANSION_NAME11 = "Midnight"
    LE_EXPANSION_LEVEL_CURRENT = 11
    GetBuildInfo = function() return "12.0.7", "66666", "Oct 1 2026", build end
    EJ_GetNumTiers = function() count() return #tiers end
    EJ_GetTierInfo = function(i) count() return tiers[i] end
    EJ_GetCurrentTier = function() count() return selected end
    EJ_SelectTier = function(t) count() selected = t; calls.select[#calls.select + 1] = t end
    EJ_GetInstanceByIndex = function(i, isRaid)
      count()
      local e = list(isRaid)[i]
      if e then return e[1], e[2] end
    end
    EJ_GetInstanceInfo = function(id)
      count()
      return info[id][2], "", "", "", "", "", 0, "", false, info[id][3]
    end
    EJ_GetEncounterInfoByIndex = function(j, id)
      count()
      if j <= info[id][4] then return "Boss" .. j end
    end
    C_ChallengeMode = {
      GetMapTable = function() count() return { 501, 502 } end,
      GetMapUIInfo = function(id)
        count()
        if id == 501 then return "Dun A", 501, 1800, 1, 2, 2001 end
        return "Old Dun", 502, 1800, 1, 2, 2002
      end,
    }
  end

  before_each(function()
    ns = loader.load({ "Core/Init.lua", "Core/DB.lua", "Core/Season.lua" })
    ns.DB:Init(nil)
    stubEJ()
  end)

  it("raids from current tier excluding world boss instance", function()
    local s = ns.Season:Get()
    assert.same({ { mapID = 2100, name = "Raid A", bosses = 3 } }, s.raids)
  end)

  it("dungeons merge M+ maps without duplicates", function()
    local s = ns.Season:Get()
    local names = {}
    for i, d in ipairs(s.dungeons) do names[i] = d.name end
    assert.same({ "Dun A", "Old Dun" }, names)
    assert.equals(2002, s.dungeons[2].mapID)
    assert.same({ { challengeMapID = 501, mapID = 2001, name = "Dun A" },
                  { challengeMapID = 502, mapID = 2002, name = "Old Dun" } }, s.mplus)
  end)

  it("restores previously selected tier", function()
    selected = 1
    ns.Season:Get()
    assert.same({ 2, 1 }, calls.select)
    assert.equals(1, selected)
  end)

  it("caches per build", function()
    ns.Season:Get()
    calls.ej = 0
    ns.Season:Get()
    assert.equals(0, calls.ej)
    assert.equals(120007, ns.db.season.build)
    build = 120008
    ns.Season:Get()
    assert.truthy(calls.ej > 0)
    assert.equals(120008, ns.db.season.build)
  end)

  it("rebuilds an empty cache", function()
    ns.db.season = { build = 120007, raids = {}, dungeons = {}, mplus = {} }
    local s = ns.Season:Get()
    assert.equals(1, #s.raids)
  end)

  it("leaves the tier alone and still returns M+ when the expansion tier is missing", function()
    EXPANSION_NAME11 = "Nope"
    local s = ns.Season:Get()
    assert.same({}, s.raids)
    assert.same({}, calls.select)
    assert.equals(2, #s.mplus)
    assert.equals(2, #s.dungeons)
  end)
end)
