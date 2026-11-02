local loader = require("tests.loader")

describe("DB", function()
  local ns

  before_each(function()
    ns = loader.load(loader.CORE)
  end)

  it("fresh init", function()
    local db = ns.DB:Init(nil)
    assert.equals(2, LockoutDB.schema)
    assert.equals(10, LockoutDB.settings.minLevel)
    assert.equals("ilvl", LockoutDB.settings.sortKey)
    assert.equals(db, LockoutDB)
    assert.equals(db, ns.db)
    assert.same({}, db.characters)
  end)

  it("fills missing settings without overwriting", function()
    ns.DB:Init({ schema = 1, settings = { minLevel = 1 }, characters = {} })
    assert.equals(1, LockoutDB.settings.minLevel)
    assert.is_false(LockoutDB.settings.minimap.hide)
  end)

  it("fills nested defaults inside existing tables", function()
    ns.DB:Init({ schema = 1, settings = { minimap = { angle = 45 } }, characters = {} })
    assert.is_false(LockoutDB.settings.minimap.hide)
    assert.equals(45, LockoutDB.settings.minimap.angle)
  end)

  it("does not share default tables between inits", function()
    local a = ns.DB:Init(nil)
    a.settings.favorites["x"] = true
    local b = ns.DB:Init(nil)
    assert.is_nil(b.settings.favorites["x"])
  end)

  it("schema 2 drops the legacy-columns setting", function()
    ns.DB:Init({ schema = 1, settings = { showLegacy = true, minLevel = 5 }, characters = {} })
    assert.equals(2, LockoutDB.schema)
    assert.is_nil(LockoutDB.settings.showLegacy)
    assert.equals(5, LockoutDB.settings.minLevel)
  end)

  it("runs migrations in order", function()
    local ran = {}
    ns.DB.SCHEMA = 3
    ns.DB.migrations[2] = function() ran[#ran + 1] = 2 end
    ns.DB.migrations[3] = function() ran[#ran + 1] = 3 end
    ns.DB:Init({ schema = 1, settings = {}, characters = {} })
    assert.same({ 2, 3 }, ran)
    assert.equals(3, LockoutDB.schema)
  end)

  it("Current creates full record", function()
    ns.DB:Init(nil)
    local rec = ns.DB:Current()
    for _, key in ipairs({ "meta", "instances", "worldBosses", "vault", "mythicPlus",
      "delves", "equipment", "bags", "watchlist", "legacyBosses", "holidays" }) do
      assert.equals("table", type(rec[key]), key)
    end
    assert.same({}, rec.bags.counts)
    assert.same({}, rec.delves.currencies)
    assert.same({}, rec.vault.activities)
    assert.same({}, rec.holidays.active)
    assert.same({}, rec.holidays.done)
    assert.equals(rec, ns.DB:Current())
    assert.equals(rec, ns.db.characters["Player-1-0001"])
  end)

  it("Current fills sections missing from a partial record", function()
    ns.DB:Init({ schema = 1, settings = {}, characters = { ["Player-1-0001"] = { meta = { name = "Thrall" } } } })
    local rec = ns.DB:Current()
    assert.equals("Thrall", rec.meta.name)
    assert.same({}, rec.bags.counts)
    assert.equals("table", type(rec.legacyBosses))
    assert.equals("table", type(rec.holidays.active))
    assert.equals("table", type(rec.holidays.done))
  end)

  it("Forget refuses current character", function()
    ns.DB:Init(nil)
    local rec = ns.DB:Current()
    assert.is_false(ns.DB:Forget("Player-1-0001"))
    assert.equals(rec, ns.db.characters["Player-1-0001"])
  end)

  it("Forget refuses unknown guid", function()
    ns.DB:Init(nil)
    assert.is_false(ns.DB:Forget("Player-1-9999"))
  end)

  it("Forget removes other and favorite", function()
    ns.DB:Init(nil)
    ns.db.characters["Player-1-0002"] = { meta = {} }
    ns.db.settings.favorites["Player-1-0002"] = true
    local fired = 0
    ns.On("DATA_UPDATED", function() fired = fired + 1 end)
    assert.is_true(ns.DB:Forget("Player-1-0002"))
    assert.is_nil(ns.db.characters["Player-1-0002"])
    assert.is_nil(ns.db.settings.favorites["Player-1-0002"])
    assert.equals(1, fired)
  end)
end)
