local loader = require("tests.loader")

describe("Reset", function()
  local R

  before_each(function()
    R = loader.load(loader.CORE).Reset
  end)

  it("Absolute", function()
    assert.equals(1500, R.Absolute(1000, 500))
    assert.is_nil(R.Absolute(1000, nil))
  end)

  it("IsExpired boundary", function()
    assert.is_false(R.IsExpired({ resetAt = 100 }, 99))
    assert.is_true(R.IsExpired({ resetAt = 100 }, 100))
  end)

  it("nil entry expired, missing resetAt not", function()
    assert.is_true(R.IsExpired(nil, 1))
    assert.is_false(R.IsExpired({}, 1))
  end)

  it("Active filters", function()
    local map = { a = { resetAt = 50 }, b = { resetAt = 150 }, c = {} }
    local out = R.Active(map, 100)
    assert.is_nil(out.a)
    assert.equals(map.b, out.b)
    assert.equals(map.c, out.c)
    assert.is_true(out ~= map)
  end)

  it("vault not expired", function()
    local v = { resetAt = 200, unclaimed = true, activities = { { threshold = 1, progress = 0 } } }
    local out = R.Vault(v, 100)
    assert.is_true(out.ready)
    assert.equals(v.activities, out.activities)
    assert.is_false(R.Vault({ resetAt = 200, activities = {} }, 100).ready)
  end)

  it("vault expired with completed slot is ready and zeroed", function()
    local v = { resetAt = 100, activities = { { threshold = 1, progress = 2, rewardIlvl = 678 } } }
    local out = R.Vault(v, 100)
    assert.is_true(out.ready)
    assert.equals(0, out.activities[1].progress)
    assert.is_nil(out.activities[1].rewardIlvl)
    assert.equals(1, out.activities[1].threshold)
    assert.equals(2, v.activities[1].progress) -- stored data untouched
  end)

  it("vault expired no progress not ready", function()
    local v = { resetAt = 100, activities = { { threshold = 2, progress = 1, rewardIlvl = nil } } }
    local out = R.Vault(v, 200)
    assert.is_false(out.ready)
    assert.equals(0, out.activities[1].progress)
  end)

  it("vault expired but unclaimed stays ready", function()
    local out = R.Vault({ resetAt = 100, unclaimed = true, activities = {} }, 200)
    assert.is_true(out.ready)
  end)

  it("vault missing is empty and not ready", function()
    local out = R.Vault(nil, 100)
    assert.is_false(out.ready)
    assert.same({}, out.activities)
  end)

  it("mythic plus not expired passes through", function()
    local mp = { resetAt = 200, key = { mapID = 501, level = 10 }, weeklyBest = 9, runs = { 1, 2 }, rating = 100, seasonBest = {} }
    local out = R.MythicPlus(mp, 100)
    assert.equals(mp.key, out.key)
    assert.equals(9, out.weeklyBest)
    assert.equals(mp.runs, out.runs)
  end)

  it("mythic plus expired keeps rating", function()
    local mp = { resetAt = 100, key = { mapID = 501, level = 10 }, weeklyBest = 9, runs = { 1 }, rating = 2500, seasonBest = { [501] = 12 } }
    local out = R.MythicPlus(mp, 100)
    assert.is_nil(out.key)
    assert.equals(0, out.weeklyBest)
    assert.same({}, out.runs)
    assert.equals(2500, out.rating)
    assert.same({ [501] = 12 }, out.seasonBest)
  end)

  it("mythic plus defaults", function()
    local out = R.MythicPlus({}, 100)
    assert.equals(0, out.rating)
    assert.same({}, out.seasonBest)
    assert.same({}, R.MythicPlus(nil, 100).runs)
  end)
end)
