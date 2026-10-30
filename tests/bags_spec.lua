local mock = require("tests.wow_mock")
local loader = require("tests.loader")

describe("Bags collector", function()
  local contents, queried -- contents[bag][slot] = { itemID, stackCount }

  local function stubs()
    contents, queried = {}, {}
    C_Container = {
      GetContainerNumSlots = function(bag)
        queried[bag] = true
        local n = 0
        for slot in pairs(contents[bag] or {}) do n = math.max(n, slot) end
        return n
      end,
      GetContainerItemInfo = function(bag, slot)
        local item = contents[bag] and contents[bag][slot]
        if item then return { itemID = item[1], stackCount = item[2] } end
      end,
    }
  end

  local function setup()
    local ns = loader.load({
      "Core/Init.lua", "Core/Util.lua", "Core/DB.lua", "Core/Watchlist.lua",
      "Data/Consumables.lua", "Collectors/Bags.lua",
    }, stubs)
    ns.DB:Init(nil)
    ns.Consumables.items[500] = "Flasks"
    return ns, ns.collectors.Bags, ns.DB:Current()
  end

  it("is registered with its events and requirements", function()
    local _, def = setup()
    assert.same({ "BAG_UPDATE_DELAYED" }, def.events)
    assert.is_nil(def.disabled)
  end)

  it("counts scan-set items across bags and reagent bag", function()
    local _, def, rec = setup()
    contents[0] = { [1] = { 500, 3 } }
    contents[5] = { [2] = { 500, 2 } }
    def:Collect(rec, mock.now)
    assert.same({ scannedAt = mock.now, counts = { [500] = 5 } }, rec.bags)
  end)

  it("ignores non-scan items", function()
    local _, def, rec = setup()
    contents[0] = { [1] = { 999, 20 }, [2] = { 500, 1 } }
    def:Collect(rec, mock.now)
    assert.same({ [500] = 1 }, rec.bags.counts)
  end)

  it("counts items on the character watchlist", function()
    local ns, def, rec = setup()
    ns.Watchlist.Set(rec, 777, true)
    contents[2] = { [1] = { 777, 4 } }
    def:Collect(rec, mock.now)
    assert.same({ [777] = 4 }, rec.bags.counts)
  end)

  it("omits zero-count items and drops stale counts", function()
    local _, def, rec = setup()
    rec.bags.counts[500] = 9
    def:Collect(rec, mock.now)
    assert.same({}, rec.bags.counts)
  end)

  it("bank containers never read", function()
    local _, def, rec = setup()
    def:Collect(rec, mock.now)
    assert.same({ [0] = true, true, true, true, true, true }, queried)
  end)

  it("rescans on WATCHLIST_CHANGED", function()
    local ns, _, rec = setup()
    ns.CollectNow("Bags")
    assert.same({}, rec.bags.counts)
    contents[0] = { [1] = { 500, 7 } }
    ns.Fire("WATCHLIST_CHANGED")
    assert.same({}, rec.bags.counts) -- debounced
    mock.advance(1)
    assert.same({ [500] = 7 }, rec.bags.counts)
    assert.equals(0, #ns.log)
  end)
end)
