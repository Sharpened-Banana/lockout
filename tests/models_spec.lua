local loader = require("tests.loader")

local NOW = 1000000

local function load()
  return loader.load({
    "Core/Init.lua", "Core/Util.lua", "Core/Reset.lua", "Data/Content.lua",
    "UI/Theme.lua", "UI/Rows.lua", "UI/Tabs/Raids.lua", "UI/Tabs/Dungeons.lua", "UI/Tabs/WorldBosses.lua", "UI/Tabs/Weekly.lua",
  })
end

local function names(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.char.meta.name end
  return out
end

local function guids(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.guid end
  return out
end

describe("Util.Duration", function()
  it("Duration formats", function()
    local d = load().Util.Duration
    assert.equals("2d 4h", d(2 * 86400 + 4 * 3600 + 59))
    assert.equals("1d 0h", d(86400))
    assert.equals("3h 5m", d(3 * 3600 + 5 * 60 + 30))
    assert.equals("1h 0m", d(3600))
    assert.equals("12m", d(12 * 60 + 59))
    assert.equals("<1m", d(59))
    assert.equals("<1m", d(0))
    assert.equals("<1m", d(-30))
  end)
end)

describe("Rows", function()
  local ns, db

  before_each(function()
    ns = load()
    UnitGUID = function() return "g-me" end
    db = {
      characters = {
        ["g-me"] = { meta = { name = "Me", realm = "R", level = 5, ilvl = 100 } },
        ["g-a"] = { meta = { name = "Alpha", realm = "R", level = 80, ilvl = 600 } },
        ["g-b"] = { meta = { name = "Bravo", realm = "S", level = 70, ilvl = 650 } },
        ["g-c"] = { meta = { name = "Charlie", realm = "R", level = 80, ilvl = 620 } },
        ["g-low"] = { meta = { name = "Low", realm = "R", level = 12, ilvl = 300 } },
        ["g-nolevel"] = { meta = { name = "Nolevel", realm = "R" } },
      },
    }
  end)

  it("min level hides but keeps current", function()
    local rows = ns.Rows.Build(db, { minLevel = 60, sortKey = "name" })
    assert.same({ "Alpha", "Bravo", "Charlie", "Me" }, names(rows))
    assert.equals("g-me", rows[4].guid)
    assert.equals(db.characters["g-me"], rows[4].char)
  end)

  it("realm only", function()
    local rows = ns.Rows.Build(db, { minLevel = 60, realmOnly = true, realm = "R", sortKey = "name" })
    assert.same({ "Alpha", "Charlie", "Me" }, names(rows))
    rows = ns.Rows.Build(db, { minLevel = 60, realmOnly = true, realm = "S", sortKey = "name" })
    assert.same({ "Bravo" }, names(rows))
  end)

  it("favorites first then ilvl desc", function()
    local rows = ns.Rows.Build(db, {
      minLevel = 60, sortKey = "ilvl", sortDesc = true, favorites = { ["g-a"] = true, ["g-me"] = true },
    })
    assert.same({ "Alpha", "Me", "Bravo", "Charlie" }, names(rows))
  end)

  it("sorts by level and name, ascending and descending", function()
    local rows = ns.Rows.Build(db, { sortKey = "level", sortDesc = true })
    assert.same({ "Alpha", "Charlie", "Bravo", "Low", "Me", "Nolevel" }, names(rows))
    rows = ns.Rows.Build(db, { sortKey = "name", sortDesc = true })
    assert.same({ "Nolevel", "Me", "Low", "Charlie", "Bravo", "Alpha" }, names(rows))
    rows = ns.Rows.Build(db, { sortKey = "ilvl" })
    assert.same({ "Nolevel", "Me", "Low", "Alpha", "Charlie", "Bravo" }, names(rows))
  end)

  it("missing level counts as 0", function()
    local rows = ns.Rows.Build(db, { minLevel = 1, sortKey = "name" })
    assert.same({ "Alpha", "Bravo", "Charlie", "Low", "Me" }, names(rows))
    rows = ns.Rows.Build(db, { minLevel = 0, sortKey = "name" })
    assert.same({ "Alpha", "Bravo", "Charlie", "Low", "Me", "Nolevel" }, names(rows))
    rows = ns.Rows.Build(db, { sortKey = "name" })
    assert.equals(6, #rows)
  end)

  it("filter is plain text", function()
    db.characters = {
      ["g-me"] = { meta = { name = "Me", realm = "R", level = 80 } },
      ["g-1"] = { meta = { name = "Xa-bY", realm = "R", level = 80 } },
      ["g-2"] = { meta = { name = "Thrall", realm = "R", level = 80 } },
    }
    assert.same({ "Xa-bY" }, names(ns.Rows.Build(db, { filter = "a-b" })))
    assert.same({}, names(ns.Rows.Build(db, { filter = "%" })))
    assert.same({}, names(ns.Rows.Build(db, { filter = "(" })))
    assert.same({}, names(ns.Rows.Build(db, { filter = "." })))
    assert.same({ "Thrall" }, names(ns.Rows.Build(db, { filter = "THR" })))
  end)

  it("disambiguates duplicate names", function()
    db.characters = {
      ["g-1"] = { meta = { name = "Thrall", realm = "Draenor", level = 80 } },
      ["g-2"] = { meta = { name = "Thrall", realm = "Silvermoon", level = 80 } },
      ["g-3"] = { meta = { name = "Jaina", realm = "Draenor", level = 80 } },
    }
    local rows = ns.Rows.Build(db, { sortKey = "name" })
    assert.same({ "g-3", "g-1", "g-2" }, guids(rows))
    assert.equals("Jaina", rows[1].label)
    assert.equals("Thrall-Draenor", rows[2].label)
    assert.equals("Thrall-Silvermoon", rows[3].label)
  end)

  it("only included rows count for name collisions", function()
    db.characters = {
      ["g-1"] = { meta = { name = "Thrall", realm = "Draenor", level = 80 } },
      ["g-2"] = { meta = { name = "Thrall", realm = "Silvermoon", level = 3 } },
    }
    local rows = ns.Rows.Build(db, { minLevel = 10 })
    assert.equals("Thrall", rows[1].label)
  end)

  it("ties fall back to name then guid", function()
    db.characters = {
      ["g-2"] = { meta = { name = "Same", realm = "B", level = 80, ilvl = 600 } },
      ["g-1"] = { meta = { name = "Same", realm = "A", level = 80, ilvl = 600 } },
      ["g-3"] = { meta = { name = "Abe", realm = "A", level = 80, ilvl = 600 } },
    }
    assert.same({ "g-3", "g-1", "g-2" }, guids(ns.Rows.Build(db, { sortKey = "ilvl", sortDesc = true })))
  end)

  it("builds from empty and meta-less records", function()
    db.characters = { ["g-x"] = {}, ["g-y"] = { meta = {} } }
    local rows = ns.Rows.Build(db, {})
    assert.equals(2, #rows)
    assert.equals("", rows[1].label)
    assert.same({}, ns.Rows.Build({ characters = {} }, {}))
  end)
end)

describe("Tab models", function()
  local ns, ctx, season

  before_each(function()
    ns = load()
    season = {
      raids = { { mapID = 100, name = "Alpha Keep", bosses = 8 }, { mapID = 200, name = "Beta Hall", bosses = 6 } },
      dungeons = { { mapID = 10, name = "Crypt" }, { mapID = 20, name = "Docks" } },
      mplus = { { challengeMapID = 501, mapID = 10, name = "Crypt" }, { challengeMapID = 502, mapID = 20, name = "Docks" } },
    }
    ctx = { db = { characters = {} }, season = season, settings = {}, now = NOW }
  end)

  local function colByKey(tab, key)
    for _, c in ipairs(tab.Columns(ctx)) do
      if c.key == key then return c end
    end
    error("no column " .. tostring(key))
  end

  it("registers the tabs in order", function()
    assert.same({ "Raids", "Dungeons", "WorldBosses", "Weekly" }, ns.TabOrder)
    for i, name in ipairs(ns.TabOrder) do
      local tab = ns.Tabs[name]
      assert.equals("string", type(tab.title))
      assert.equals(i, tab.order)
    end
  end)

  describe("Raids", function()
    local function inst(mapID, diff, diffName, killed, total, resetAt, name)
      local encounters = {}
      for i = 1, total do encounters[i] = { name = "Boss" .. i, killed = i <= killed } end
      return {
        name = name or "Alpha Keep", mapID = mapID, difficultyID = diff, difficultyName = diffName, isRaid = true,
        resetAt = resetAt, killed = killed, total = total, encounters = encounters,
      }
    end

    it("columns come from the season", function()
      local cols = ns.Tabs.Raids.Columns(ctx)
      assert.equals(2, #cols)
      assert.equals(100, cols[1].key)
      assert.equals("Alpha Keep", cols[1].label)
      assert.equals("number", type(cols[1].width))
    end)

    it("cell badges and color", function()
      local char = { instances = {
        ["100:14"] = inst(100, 14, "Normal", 8, 8, NOW + 3 * 86400 + 5 * 3600),
        ["100:15"] = inst(100, 15, "Heroic", 4, 8, NOW + 3 * 86400 + 5 * 3600),
      } }
      local cell = ns.Tabs.Raids.Cell(char, colByKey(ns.Tabs.Raids, 100), ctx)
      assert.equals("N 8/8  H 4/8", cell.text)
      assert.same(ns.Rows.COLORS.yellow, cell.color)
      assert.equals("Normal", cell.tooltip[1].left)
      assert.equals("resets in 3d 5h", cell.tooltip[1].right)
      assert.equals("Boss1", cell.tooltip[2].left)
      assert.equals("Killed", cell.tooltip[2].right)
      -- header, 8 bosses, header, 8 bosses
      assert.equals(18, #cell.tooltip)
      assert.equals("Heroic", cell.tooltip[10].left)
      assert.equals("Alive", cell.tooltip[10 + 5].right)
    end)

    it("green when the highest shown difficulty is full", function()
      local char = { instances = {
        ["100:14"] = inst(100, 14, "Normal", 2, 8, NOW + 100),
        ["100:15"] = inst(100, 15, "Heroic", 8, 8, NOW + 100),
      } }
      local cell = ns.Tabs.Raids.Cell(char, colByKey(ns.Tabs.Raids, 100), ctx)
      assert.equals("N 2/8  H 8/8", cell.text)
      assert.same(ns.Rows.COLORS.green, cell.color)
    end)

    it("orders LFR, N, H, M and names other difficulties by first letter", function()
      local char = { instances = {
        ["100:16"] = inst(100, 16, "Mythic", 1, 8, NOW + 100),
        ["100:17"] = inst(100, 17, "Looking For Raid", 8, 8, NOW + 100),
        ["100:15"] = inst(100, 15, "Heroic", 3, 8, NOW + 100),
        ["100:14"] = inst(100, 14, "Normal", 5, 8, NOW + 100),
      } }
      local col = colByKey(ns.Tabs.Raids, 100)
      assert.equals("L 8/8  N 5/8  H 3/8  M 1/8", ns.Tabs.Raids.Cell(char, col, ctx).text)
      char = { instances = { ["100:99"] = inst(100, 99, "Timewalking", 1, 4, NOW + 100) } }
      assert.equals("T 1/4", ns.Tabs.Raids.Cell(char, col, ctx).text)
    end)

    it("expired lockout empty", function()
      local char = { instances = { ["100:14"] = inst(100, 14, "Normal", 8, 8, NOW - 1) } }
      local cell = ns.Tabs.Raids.Cell(char, colByKey(ns.Tabs.Raids, 100), ctx)
      assert.equals("–", cell.text)
      assert.is_nil(cell.color)
    end)

    it("ignores other maps", function()
      local char = { instances = { ["200:14"] = inst(200, 14, "Normal", 8, 8, NOW + 100) } }
      assert.equals("–", ns.Tabs.Raids.Cell(char, colByKey(ns.Tabs.Raids, 100), ctx).text)
    end)

    it("legacy columns only when enabled", function()
      ctx.db.characters["g1"] = { instances = {
        ["100:14"] = inst(100, 14, "Normal", 1, 8, NOW + 100),
        ["300:14"] = inst(300, 14, "Normal", 1, 5, NOW + 100, "Zeta Ruins"),
        ["400:14"] = inst(400, 14, "Normal", 1, 5, NOW + 100, "Old Sanctum"),
        ["500:23"] = { name = "Some Dungeon", mapID = 500, difficultyID = 23, isRaid = false, resetAt = NOW + 100 },
        ["600:14"] = inst(600, 14, "Normal", 1, 5, NOW - 5, "Expired Raid"),
      } }
      ctx.db.characters["g2"] = { instances = { ["300:15"] = inst(300, 15, "Heroic", 1, 5, NOW + 100, "Zeta Ruins") } }
      ctx.db.characters["g3"] = {}
      assert.equals(2, #ns.Tabs.Raids.Columns(ctx))

      ctx.settings.showLegacy = true
      local cols = ns.Tabs.Raids.Columns(ctx)
      local labels = {}
      for i, c in ipairs(cols) do labels[i] = c.label end
      assert.same({ "Alpha Keep", "Beta Hall", "Old Sanctum", "Zeta Ruins" }, labels)
      assert.equals(400, cols[3].key)
      assert.equals(300, cols[4].key)
    end)
  end)

  describe("Dungeons", function()
    it("columns come from the season", function()
      local cols = ns.Tabs.Dungeons.Columns(ctx)
      assert.equals(2, #cols)
      assert.equals(10, cols[1].key)
      assert.equals("Crypt", cols[1].label)
    end)

    it("m0 and season best", function()
      local char = {
        instances = { ["10:23"] = { mapID = 10, difficultyID = 23, resetAt = NOW + 100 } },
        mythicPlus = { seasonBest = { [501] = 12 } },
      }
      local col = colByKey(ns.Tabs.Dungeons, 10)
      assert.equals(ns.Theme.Icon.check .. " +12", ns.Tabs.Dungeons.Cell(char, col, ctx).text)
    end)

    it("shows only what exists", function()
      local col10, col20 = colByKey(ns.Tabs.Dungeons, 10), colByKey(ns.Tabs.Dungeons, 20)
      local char = {
        instances = { ["10:23"] = { mapID = 10, difficultyID = 23, resetAt = NOW + 100 } },
        mythicPlus = { seasonBest = { [502] = 9 } },
      }
      assert.equals(ns.Theme.Icon.check, ns.Tabs.Dungeons.Cell(char, col10, ctx).text)
      assert.equals("+9", ns.Tabs.Dungeons.Cell(char, col20, ctx).text)
    end)

    it("expired m0 is not shown", function()
      local char = { instances = { ["10:23"] = { mapID = 10, difficultyID = 23, resetAt = NOW - 1 } } }
      assert.equals("–", ns.Tabs.Dungeons.Cell(char, colByKey(ns.Tabs.Dungeons, 10), ctx).text)
    end)

    it("only mythic 0 counts, not other difficulties", function()
      local char = { instances = { ["10:8"] = { mapID = 10, difficultyID = 8, resetAt = NOW + 100 } } }
      assert.equals("–", ns.Tabs.Dungeons.Cell(char, colByKey(ns.Tabs.Dungeons, 10), ctx).text)
    end)
  end)

  describe("WorldBosses", function()
    it("columns are empty when nothing is known", function()
      assert.same({}, ns.Tabs.WorldBosses.Columns(ctx))
    end)

    it("columns from content then seen keys", function()
      ns.Content.WORLD_BOSSES[1] = { key = "q111", questID = 111, name = "Known Boss" }
      ctx.db.characters["g1"] = { worldBosses = {
        q111 = { name = "Known Boss", resetAt = NOW + 100 },
        wb7 = { name = "Zed", resetAt = NOW + 100 },
        wb8 = { name = "Old", resetAt = NOW - 1 },
      } }
      ctx.db.characters["g2"] = { worldBosses = { q222 = { name = "Alpha", resetAt = NOW + 100 } } }
      local cols = ns.Tabs.WorldBosses.Columns(ctx)
      local labels = {}
      for i, c in ipairs(cols) do labels[i] = c.key .. "=" .. c.label end
      assert.same({ "q111=Known Boss", "q222=Alpha", "wb7=Zed" }, labels)
    end)

    it("cell shows a check when active", function()
      local char = { worldBosses = {
        wb7 = { name = "Zed", resetAt = NOW + 3600 },
        wb8 = { name = "Old", resetAt = NOW - 1 },
      } }
      local on = ns.Tabs.WorldBosses.Cell(char, { key = "wb7" }, ctx)
      assert.equals(ns.Theme.Icon.check, on.text)
      assert.same(ns.Rows.COLORS.green, on.color)
      assert.equals("resets in 1h 0m", on.tooltip[1].right)
      assert.equals("–", ns.Tabs.WorldBosses.Cell(char, { key = "wb8" }, ctx).text)
      assert.equals("–", ns.Tabs.WorldBosses.Cell(char, { key = "wb9" }, ctx).text)
    end)
  end)

  describe("Weekly", function()
    local function vault(resetAt, unclaimed, activities)
      return { resetAt = resetAt, unclaimed = unclaimed, activities = activities }
    end
    local function activity(type, index, threshold, progress, rewardIlvl)
      return { type = type, index = index, threshold = threshold, progress = progress, level = 0, rewardIlvl = rewardIlvl }
    end
    local function cell(char, key)
      return ns.Tabs.Weekly.Cell(char, colByKey(ns.Tabs.Weekly, key), ctx)
    end

    it("columns", function()
      local keys = {}
      for i, c in ipairs(ns.Tabs.Weekly.Columns(ctx)) do keys[i] = c.key end
      assert.same({ "vaultRaid", "vaultDungeons", "vaultWorld", "key", "rating", "delves", "ready" }, keys)
    end)

    it("vault cell", function()
      local T = Enum.WeeklyRewardChestThresholdType
      local char = { vault = vault(NOW + 100, false, {
        activity(T.Raid, 1, 2, 2, 661), activity(T.Raid, 2, 4, 2, nil), activity(T.Raid, 3, 6, 0, nil),
        activity(T.Activities, 1, 1, 1, 678), activity(T.Activities, 2, 4, 4, 665), activity(T.Activities, 3, 8, 3, nil),
      }) }
      local c = cell(char, "vaultDungeons")
      assert.equals("2/3 · 678", c.text)
      assert.equals("1/3 · 661", cell(char, "vaultRaid").text)
      assert.equals("–", cell(char, "vaultWorld").text)
      assert.truthy(#c.tooltip >= 3)
    end)

    it("vault cell without reward level", function()
      local T = Enum.WeeklyRewardChestThresholdType
      local char = { vault = vault(NOW + 100, false, {
        activity(T.World, 1, 2, 1, nil), activity(T.World, 2, 4, 1, nil), activity(T.World, 3, 8, 1, nil),
      }) }
      assert.equals("0/3", cell(char, "vaultWorld").text)
    end)

    it("ready flag after reset", function()
      local T = Enum.WeeklyRewardChestThresholdType
      local acts = { activity(T.Raid, 1, 2, 2, 661), activity(T.Raid, 2, 4, 1, nil), activity(T.Raid, 3, 6, 0, nil) }
      local char = { vault = vault(NOW - 10, false, acts) }
      assert.equals(ns.Theme.Icon.vault, cell(char, "ready").text)
      -- progress belongs to the finished week
      assert.equals("0/3", cell(char, "vaultRaid").text)
      char = { vault = vault(NOW + 10, false, acts) }
      assert.equals("–", cell(char, "ready").text)
      char = { vault = vault(NOW + 10, true, acts) }
      assert.equals(ns.Theme.Icon.vault, cell(char, "ready").text)
    end)

    it("key name from season", function()
      local char = { mythicPlus = { resetAt = NOW + 100, key = { challengeMapID = 502, level = 14 } } }
      assert.equals("+14 Docks", cell(char, "key").text)
      char.mythicPlus.key = { challengeMapID = 999, level = 3 }
      assert.equals("+3", cell(char, "key").text)
      char.mythicPlus.key = nil
      assert.equals("–", cell(char, "key").text)
    end)

    it("expired key is not shown", function()
      local char = { mythicPlus = { resetAt = NOW - 1, key = { challengeMapID = 502, level = 14 } } }
      assert.equals("–", cell(char, "key").text)
    end)

    it("rating", function()
      assert.equals("2456", cell({ mythicPlus = { rating = 2456 } }, "rating").text)
      assert.equals("–", cell({ mythicPlus = { rating = 0 } }, "rating").text)
    end)

    it("delves show dash without configured currencies", function()
      local char = { delves = { updatedAt = NOW - 120, currencies = { [1] = 5 } } }
      assert.equals("–", cell(char, "delves").text)
    end)

    it("delves join quantities with an age tooltip", function()
      ns.Content.DELVE_CURRENCIES[1] = { id = 1, name = "Shards" }
      ns.Content.DELVE_CURRENCIES[2] = { id = 2, name = "Keys" }
      local char = { delves = { updatedAt = NOW - 7200, currencies = { [1] = 150, [2] = 3 } } }
      local c = cell(char, "delves")
      assert.equals("150 / 3", c.text)
      assert.equals("Shards", c.tooltip[1].left)
      assert.equals("150", c.tooltip[1].right)
      assert.equals("updated 2h ago", c.tooltip[#c.tooltip].left)
      assert.equals("–", cell({ delves = { currencies = {} } }, "delves").text)
    end)
  end)

  it("renders empty record", function()
    ns.Content.WORLD_BOSSES[1] = { key = "q111", questID = 111, name = "Known Boss" }
    ns.Content.DELVE_CURRENCIES[1] = { id = 1, name = "Shards" }
    ctx.settings.showLegacy = true
    ctx.db.characters["g-seen"] = { worldBosses = { wb7 = { name = "Zed", resetAt = NOW + 100 } } }
    local variants = {
      { meta = { name = "X" } },
      {},
      { meta = { name = "X" }, instances = {}, worldBosses = {}, vault = {}, mythicPlus = {}, delves = {} },
      { meta = { name = "X" }, vault = { activities = {} }, mythicPlus = { seasonBest = {} }, delves = { currencies = {} } },
    }
    for _, char in ipairs(variants) do
      for _, name in ipairs(ns.TabOrder) do
        local tab = ns.Tabs[name]
        local cols = tab.Columns(ctx)
        assert.truthy(#cols > 0)
        for _, col in ipairs(cols) do
          local cell = tab.Cell(char, col, ctx)
          assert.equals("–", cell.text)
        end
      end
    end
  end)

  it("tabs cope with a missing season", function()
    ctx.season = nil
    for _, name in ipairs(ns.TabOrder) do
      local tab = ns.Tabs[name]
      for _, col in ipairs(tab.Columns(ctx)) do
        assert.equals("–", tab.Cell({ meta = { name = "X" } }, col, ctx).text)
      end
    end
  end)
end)

describe("Theme status markers", function()
  it("are texture markup, not font glyphs", function()
    local ns = load()
    for _, key in ipairs({ "check", "vault", "socket" }) do
      local markup = ns.Theme.Icon[key]
      assert.equals("string", type(markup))
      assert.truthy(markup:find("^|T[^|]+|t$"))
    end
  end)
end)
