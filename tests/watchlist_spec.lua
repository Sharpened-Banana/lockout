local loader = require("tests.loader")

describe("Watchlist", function()
  local ns, W

  before_each(function()
    ns = loader.load(loader.CORE)
    ns.Consumables.items = { [1001] = "Flasks", [1002] = "Potions" }
    W = ns.Watchlist
  end)

  it("Consumables.CategoryOf maps known ids and falls back to Other", function()
    assert.same({ "Flasks", "Potions", "Food", "Runes", "Oils" }, ns.Consumables.CATEGORIES)
    assert.equals("Flasks", ns.Consumables.CategoryOf(1001))
    assert.equals("Other", ns.Consumables.CategoryOf(9999))
  end)

  it("works with the shipped data table", function()
    local real = loader.load(loader.CORE)
    for id, cat in pairs(real.Consumables.items) do
      assert.equals("number", type(id))
      assert.equals(cat, real.Consumables.CategoryOf(id))
    end
  end)

  it("default shown when nil", function()
    assert.is_true(W.IsDefault(1001))
    assert.is_false(W.IsDefault(2001))
    assert.is_true(W.IsShown({ watchlist = {} }, 1001))
    assert.is_false(W.IsShown({ watchlist = {} }, 2001))
  end)

  it("false hides default", function()
    assert.is_false(W.IsShown({ watchlist = { [1001] = false } }, 1001))
  end)

  it("true shows custom", function()
    assert.is_true(W.IsShown({ watchlist = { [2001] = true } }, 2001))
  end)

  it("Set back on default stores nil", function()
    local char = { watchlist = { [1001] = false } }
    W.Set(char, 1001, true)
    assert.is_nil(char.watchlist[1001])
    W.Set(char, 1001, false)
    assert.is_false(char.watchlist[1001])
  end)

  it("Set on custom stores true, off stores false", function()
    local char = { watchlist = {} }
    W.Set(char, 2001, true)
    assert.is_true(char.watchlist[2001])
    W.Set(char, 2001, false)
    assert.is_false(char.watchlist[2001])
  end)

  it("ScanSet unions defaults and any char's true", function()
    local db = { characters = {
      A = { watchlist = { [2001] = true } },
      B = { watchlist = { [2002] = false } },
      C = {},
    } }
    assert.same({ [1001] = true, [1002] = true, [2001] = true }, W.ScanSet(db))
  end)

  it("Groups hides off items unless editing", function()
    local char = { watchlist = { [1002] = false }, bags = { counts = { [1001] = 3 } } }
    local db = { characters = { x = char } }
    local g = W.Groups(char, db, false)
    assert.equals(1, #g)
    assert.equals("Flasks", g[1].category)
    assert.same({ { itemID = 1001, count = 3, shown = true } }, g[1].items)

    local e = W.Groups(char, db, true)
    assert.equals(2, #e)
    assert.equals("Potions", e[2].category)
    assert.same({ { itemID = 1002, count = 0, shown = false } }, e[2].items)
  end)

  it("Groups puts custom under Other and orders categories", function()
    ns.Consumables.items = { [1003] = "Potions", [1001] = "Flasks", [1002] = "Flasks" }
    local char = { watchlist = { [3001] = true, [2001] = true }, bags = { counts = {} } }
    local g = W.Groups(char, { characters = { x = char } }, false)
    assert.equals("Flasks", g[1].category)
    assert.equals(1001, g[1].items[1].itemID)
    assert.equals(1002, g[1].items[2].itemID)
    assert.equals("Potions", g[2].category)
    assert.equals("Other", g[3].category)
    assert.equals(2001, g[3].items[1].itemID)
    assert.equals(3001, g[3].items[2].itemID)
  end)

  it("Groups editing lists custom items from other characters as not shown", function()
    local a = { watchlist = { [2001] = true }, bags = { counts = {} } }
    local b = { watchlist = {}, bags = { counts = {} } }
    local db = { characters = { a = a, b = b } }
    local g = W.Groups(b, db, true)
    assert.equals("Other", g[#g].category)
    assert.is_false(g[#g].items[1].shown)
  end)

  it("Groups folds unknown categories into Other", function()
    ns.Consumables.items = { [1001] = "Bogus" }
    local g = W.Groups({ watchlist = {} }, { characters = {} }, false)
    assert.equals(1, #g)
    assert.equals("Other", g[1].category)
    assert.equals(1001, g[1].items[1].itemID)
  end)

  it("count defaults to 0", function()
    local char = { watchlist = {} }
    local g = W.Groups(char, { characters = {} }, false)
    assert.equals(0, g[1].items[1].count)
    local bare = W.Groups({ watchlist = {}, bags = { counts = {} } }, { characters = {} }, false)
    assert.equals(0, bare[1].items[1].count)
  end)

  it("empty data yields no groups", function()
    ns.Consumables.items = {}
    assert.same({}, W.Groups({ watchlist = {} }, { characters = {} }, true))
  end)
end)
