local mock = require("tests.wow_mock")
local loader = require("tests.loader")

-- Stubs are installed before the files load: `requires` is checked at registration time.
local function loadAddon(files, install)
  local list = { "Core/Init.lua", "Core/Util.lua", "Core/DB.lua", "Data/Content.lua" }
  for _, f in ipairs(files) do list[#list + 1] = f end
  local ns = loader.load(list, install)
  ns.DB:Init(nil)
  return ns
end

describe("Character collector", function()
  local function stubs()
    GetAverageItemLevel = function() return 662.7, 660.2, 650 end
    GetSpecialization = function() return 2 end
    GetSpecializationInfo = function(i) if i == 2 then return 263 end end
    GetMoney = function() return 123450000 end
  end

  it("writes meta", function()
    local ns = loadAddon({ "Collectors/Character.lua" }, stubs)
    local def = ns.collectors.Character
    assert.same({ "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED" },
      def.events)
    local rec = ns.DB:Current()
    def:Collect(rec, mock.now)
    assert.same({
      name = "Thrall", realm = "Draenor", classFile = "SHAMAN", level = 80,
      specID = 263, ilvl = 662, ilvlEquipped = 660, gold = 123450000, lastSeen = mock.now,
    }, rec.meta)
  end)

  it("runs through the bus", function()
    local ns = loadAddon({ "Collectors/Character.lua" }, stubs)
    ns.CollectNow("Character")
    assert.equals("Thrall", ns.DB:Current().meta.name)
    assert.equals(0, #ns.log)
  end)

  it("has no specID without a specialization", function()
    local ns = loadAddon({ "Collectors/Character.lua" }, function()
      stubs()
      GetSpecialization = function() return nil end
    end)
    local rec = ns.DB:Current()
    ns.collectors.Character:Collect(rec, mock.now)
    assert.is_nil(rec.meta.specID)
    assert.equals(662, rec.meta.ilvl)
  end)

  it("still writes meta when the spec APIs are missing", function()
    local ns = loadAddon({ "Collectors/Character.lua" }, function()
      stubs()
      GetSpecialization, GetSpecializationInfo = nil, nil
    end)
    ns.CollectNow("Character")
    local meta = ns.DB:Current().meta
    assert.equals(0, #ns.log)
    assert.equals("Thrall", meta.name)
    assert.equals(80, meta.level)
    assert.equals(662, meta.ilvl)
    assert.is_nil(meta.specID)
  end)

  it("prefers C_SpecializationInfo", function()
    local ns = loadAddon({ "Collectors/Character.lua" }, function()
      stubs()
      GetSpecialization, GetSpecializationInfo = nil, nil
      C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function(i) if i == 1 then return 262 end end,
      }
    end)
    local rec = ns.DB:Current()
    ns.collectors.Character:Collect(rec, mock.now)
    assert.equals(262, rec.meta.specID)
  end)
end)

describe("Equipment collector", function()
  local links, ilvls, equipLocs, stats, tooltips

  local function link(id, enchant, g1)
    return string.format("|cffa335ee|Hitem:%d:%d:%s::::::|h[Item %d]|h|r", id, enchant, g1 or "", id)
  end

  local function tip(text)
    return { lines = { { leftText = "Some Item" }, { leftText = text } } }
  end

  local function stubs()
    links, ilvls, equipLocs, stats, tooltips = {}, {}, {}, {}, {}
    GetInventoryItemLink = function(_, slot) return links[slot] end
    C_TooltipInfo = { GetInventoryItem = function(_, slot) return tooltips[slot] end }
    C_Item = {
      GetDetailedItemLevelInfo = function(l) return ilvls[l] end,
      GetItemInfoInstant = function(l) return 1, "Armor", "Misc", equipLocs[l] end,
      GetItemStats = function(l) return stats[l] end,
    }
  end

  local function setup()
    local ns = loadAddon({ "Collectors/Equipment.lua" }, stubs)
    return ns, ns.collectors.Equipment, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("disables itself when a required API is missing", function()
    local ns = loadAddon({ "Collectors/Equipment.lua" }, function()
      stubs()
      C_TooltipInfo = nil
    end)
    assert.is_true(ns.collectors.Equipment.disabled)
  end)

  it("track, enchant, sockets", function()
    local ns, _, rec = setup()
    local chest = link(1001, 0)
    local neck = link(1002, 0, "213")
    links[5], links[2] = chest, neck
    ilvls[chest], ilvls[neck] = 671, 668
    equipLocs[chest], equipLocs[neck] = "INVTYPE_CHEST", "INVTYPE_NECK"
    stats[neck] = { EMPTY_SOCKET_PRISMATIC = 2, ITEM_MOD_STRENGTH_SHORT = 500 }
    tooltips[5] = tip("Upgrade Level: Hero 4/6")

    ns.CollectNow("Equipment")
    assert.equals(0, #ns.log)
    assert.same({
      link = chest, itemID = 1001, ilvl = 671, track = "Hero", trackCur = 4, trackMax = 6,
      missingEnchant = true, emptySockets = 0,
    }, rec.equipment[5])
    assert.is_false(rec.equipment[2].missingEnchant)
    assert.equals(1, rec.equipment[2].emptySockets)
    assert.is_nil(rec.equipment[2].track)
    assert.equals(1002, rec.equipment[2].itemID)
  end)

  it("treats an enchanted item as not missing an enchant", function()
    local _, def, rec = setup()
    local l = link(1003, 7000)
    links[1], ilvls[l], equipLocs[l] = l, 660, "INVTYPE_HEAD"
    def:Collect(rec, mock.now)
    assert.is_false(rec.equipment[1].missingEnchant)
  end)

  it("never reports negative empty sockets", function()
    local _, def, rec = setup()
    local l = link(1004, 0, "213")
    links[2], ilvls[l], equipLocs[l] = l, 660, "INVTYPE_NECK"
    stats[l] = {}
    def:Collect(rec, mock.now)
    assert.equals(0, rec.equipment[2].emptySockets)
  end)

  it("off-hand shield not enchantable", function()
    local _, def, rec = setup()
    local shield = link(1010, 0)
    local weapon = link(1011, 0)
    links[17], ilvls[shield], equipLocs[shield] = shield, 660, "INVTYPE_SHIELD"
    def:Collect(rec, mock.now)
    assert.is_false(rec.equipment[17].missingEnchant)

    links[17], ilvls[weapon], equipLocs[weapon] = weapon, 660, "INVTYPE_WEAPON"
    def:Collect(rec, mock.now)
    assert.is_true(rec.equipment[17].missingEnchant)

    local offhand = link(1012, 0)
    links[17], ilvls[offhand], equipLocs[offhand] = offhand, 660, "INVTYPE_WEAPONOFFHAND"
    def:Collect(rec, mock.now)
    assert.is_true(rec.equipment[17].missingEnchant)
  end)

  it("empty slot removed", function()
    local _, def, rec = setup()
    local l = link(1001, 0)
    links[5], ilvls[l], equipLocs[l] = l, 660, "INVTYPE_CHEST"
    def:Collect(rec, mock.now)
    assert.truthy(rec.equipment[5])
    links[5] = nil
    def:Collect(rec, mock.now)
    assert.is_nil(rec.equipment[5])
  end)

  it("uncached item", function()
    local ns, _, rec = setup()
    local l = link(1001, 0)
    links[5], equipLocs[l] = l, "INVTYPE_CHEST" -- ilvl, tooltip and stats all nil
    ns.CollectNow("Equipment")
    assert.equals(0, #ns.log)
    assert.truthy(rec.equipment[5])
    assert.equals(1001, rec.equipment[5].itemID)
    assert.is_nil(rec.equipment[5].ilvl)
    assert.is_nil(rec.equipment[5].track)
    assert.equals(0, rec.equipment[5].emptySockets)
  end)
end)
