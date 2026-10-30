local mock = require("tests.wow_mock")
local loader = require("tests.loader")

describe("collector bus", function()
  local ns, rec

  before_each(function()
    ns = loader.load({ "Core/Init.lua" })
    rec = {}
    ns.DB = { Current = function() return rec end }
  end)

  local function counter(def)
    local c = { n = 0 }
    def.Collect = function() c.n = c.n + 1 end
    ns.RegisterCollector(def)
    return c
  end

  it("debounces bursts", function()
    local c = counter({ name = "T", events = { "BAG_UPDATE_DELAYED" } })
    mock.fire("BAG_UPDATE_DELAYED")
    mock.fire("BAG_UPDATE_DELAYED")
    mock.fire("BAG_UPDATE_DELAYED")
    mock.advance(0.5)
    assert.equals(1, c.n)
    mock.fire("BAG_UPDATE_DELAYED")
    mock.advance(0.5)
    assert.equals(2, c.n)
  end)

  it("honours a custom debounce", function()
    local c = counter({ name = "T", events = { "E" }, debounce = 2 })
    mock.fire("E")
    mock.advance(1.9)
    assert.equals(0, c.n)
    mock.advance(0.1)
    assert.equals(1, c.n)
  end)

  it("defers in combat", function()
    local c = counter({ name = "T", events = { "BAG_UPDATE_DELAYED" } })
    mock.inCombat = true
    mock.fire("BAG_UPDATE_DELAYED")
    mock.advance(0.5)
    assert.equals(0, c.n)
    mock.inCombat = false
    mock.fire("PLAYER_REGEN_ENABLED")
    mock.advance(0.5)
    assert.equals(1, c.n)
    mock.fire("PLAYER_REGEN_ENABLED")
    mock.advance(0.5)
    assert.equals(1, c.n)
  end)

  it("pcall isolates failures and logs once", function()
    local second = 0
    ns.RegisterCollector({ name = "A", events = { "E" }, Collect = function() error("boom") end })
    ns.RegisterCollector({ name = "B", events = { "E" }, Collect = function() second = second + 1 end })
    mock.fire("E"); mock.advance(0.5)
    mock.fire("E"); mock.advance(0.5)
    assert.equals(2, second)
    assert.equals(1, #ns.log)
    assert.truthy(ns.log[1]:find("A failed", 1, true))
  end)

  it("disables collector with missing API", function()
    local called = 0
    ns.RegisterCollector({ name = "X", events = { "E" }, requires = { "C_Nope.Fn" },
      Collect = function() called = called + 1 end })
    assert.is_true(ns.collectors.X.disabled)
    mock.fire("E"); mock.advance(0.5)
    assert.equals(0, called)
    assert.truthy(ns.log[1]:find("missing C_Nope.Fn", 1, true))
  end)

  it("enables collector when dotted API exists", function()
    C_Present = { Fn = function() end }
    local c = counter({ name = "X", events = { "E" }, requires = { "C_Present.Fn" } })
    assert.is_nil(ns.collectors.X.disabled)
    mock.fire("E"); mock.advance(0.5)
    assert.equals(1, c.n)
  end)

  it("login calls OnLogin then collects", function()
    local order = {}
    ns.RegisterCollector({ name = "T", events = {},
      OnLogin = function() order[#order + 1] = "onlogin" end,
      Collect = function() order[#order + 1] = "collect" end })
    mock.fire("PLAYER_LOGIN")
    mock.advance(0.5)
    assert.same({ "onlogin", "collect" }, order)
  end)

  it("fires DATA_UPDATED with the collector name only on success", function()
    local got = {}
    ns.On("DATA_UPDATED", function(name) got[#got + 1] = name end)
    counter({ name = "T", events = { "E" } })
    ns.RegisterCollector({ name = "F", events = { "E" }, Collect = function() error("x") end })
    mock.fire("E"); mock.advance(0.5)
    assert.same({ "T" }, got)
  end)

  it("passes the current record and time to Collect", function()
    local gotSelf, gotRec, gotNow
    local def = { name = "T", events = { "E" }, Collect = function(self, r, now)
      gotSelf, gotRec, gotNow = self, r, now
    end }
    ns.RegisterCollector(def)
    mock.fire("E"); mock.advance(0.5)
    assert.equals(def, gotSelf)
    assert.equals(rec, gotRec)
    assert.equals(mock.now, gotNow)
  end)

  it("OnEvent runs before scheduling", function()
    local calls = {}
    local c = counter({ name = "T", events = { "E" },
      OnEvent = function(event, ...) calls[#calls + 1] = { event, ... } end })
    mock.fire("E", "a")
    mock.fire("E", "b")
    assert.equals(2, #calls)
    assert.same({ "E", "a" }, calls[1])
    assert.equals(0, c.n)
    mock.advance(0.5)
    assert.equals(1, c.n)
  end)

  it("OnEvent runs even in combat", function()
    local seen = 0
    counter({ name = "T", events = { "E" }, OnEvent = function() seen = seen + 1 end })
    mock.inCombat = true
    mock.fire("E")
    assert.equals(1, seen)
  end)

  it("CollectNow runs immediately and respects combat", function()
    local c = counter({ name = "T", events = {} })
    ns.CollectNow("T")
    assert.equals(1, c.n)
    mock.inCombat = true
    ns.CollectNow("T")
    assert.equals(1, c.n)
    mock.inCombat = false
    mock.fire("PLAYER_REGEN_ENABLED"); mock.advance(0.5)
    assert.equals(2, c.n)
  end)

  it("ADDON_LOADED for Lockout inits the DB and fires DB_READY", function()
    local inited, ready
    ns.DB.Init = function(_, saved) inited = saved end
    ns.On("DB_READY", function() ready = true end)
    LockoutDB = { marker = true }
    mock.fire("ADDON_LOADED", "OtherAddon")
    assert.is_nil(inited)
    mock.fire("ADDON_LOADED", "Lockout")
    assert.equals(LockoutDB, inited)
    assert.is_true(ready)
  end)

  it("Log formats and LogOnce dedupes by key", function()
    ns.Log("%s=%d", "a", 1)
    ns.LogOnce("k", "once %s", "x")
    ns.LogOnce("k", "once %s", "y")
    assert.same({ "a=1", "once x" }, ns.log)
  end)

  describe("slash", function()
    it("dispatches sub and rest", function()
      local got
      ns.RegisterSlash("foo", function(rest) got = rest end)
      SlashCmdList.LOCKOUT("foo bar baz")
      assert.equals("bar baz", got)
      assert.equals("/lockout", SLASH_LOCKOUT1)
      assert.equals("/lo", SLASH_LOCKOUT2)
    end)

    it("empty sub calls handler with empty string", function()
      local got
      ns.RegisterSlash("", function(rest) got = rest end)
      SlashCmdList.LOCKOUT("")
      assert.equals("", got)
      got = nil
      SlashCmdList.LOCKOUT(nil)
      assert.equals("", got)
    end)

    it("unknown sub prints usage listing subs", function()
      ns.RegisterSlash("foo", function() end)
      SlashCmdList.LOCKOUT("nope")
      assert.equals(1, #mock.printed)
      assert.truthy(mock.printed[1]:find("foo", 1, true))
      assert.truthy(mock.printed[1]:find("debug", 1, true))
    end)

    it("debug prints the log", function()
      ns.Log("hello %d", 1)
      SlashCmdList.LOCKOUT("debug")
      assert.same({ "|cff33ff99Lockout|r hello 1" }, mock.printed)
    end)
  end)
end)
