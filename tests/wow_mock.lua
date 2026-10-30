-- Minimal World of Warcraft API mock for headless tests.
local mock = {}

local timers, frames, seq

local function newPlayer()
  return { guid = "Player-1-0001", name = "Thrall", realm = "Draenor", classFile = "SHAMAN", level = 80 }
end

-- Universal stub frame: unknown methods are no-ops returning the frame.
local frameMethods = {}
local frameMeta = {}
frameMeta.__index = function(self, key)
  local m = frameMethods[key]
  if m then return m end
  local noop = function() return self end
  return noop
end

local state = setmetatable({}, { __mode = "k" }) -- frame -> { events, scripts }

function frameMethods.RegisterEvent(self, event) state[self].events[event] = true end
function frameMethods.UnregisterEvent(self, event) state[self].events[event] = nil end
function frameMethods.SetScript(self, name, fn) state[self].scripts[name] = fn end
function frameMethods.GetScript(self, name) return state[self].scripts[name] end

local function createFrame()
  local f = setmetatable({}, frameMeta)
  state[f] = { events = {}, scripts = {} }
  frames[#frames + 1] = f
  return f
end

-- Globals present before the first reset (stdlib + runner helpers) survive every reset;
-- anything else (addon globals, per-test API stubs) is removed so specs stay isolated.
local baseline

function mock.reset()
  if not baseline then
    baseline = {}
    for k in pairs(_G) do baseline[k] = true end
  else
    local stale = {}
    for k in pairs(_G) do
      if not baseline[k] then stale[#stale + 1] = k end
    end
    for _, k in ipairs(stale) do _G[k] = nil end
  end

  timers, frames, seq = {}, {}, 0
  mock.now = 1700000000
  mock.inCombat = false
  mock.player = newPlayer()
  mock.printed = {}

  time = function(tbl)
    if tbl then return os.time(tbl) end
    return mock.now
  end
  date = os.date
  C_Timer = {
    After = function(delay, fn)
      seq = seq + 1
      timers[#timers + 1] = { due = mock.now + delay, seq = seq, fn = fn }
    end,
  }
  CreateFrame = createFrame
  InCombatLockdown = function() return mock.inCombat end
  UnitGUID = function(unit) if unit == "player" then return mock.player.guid end end
  UnitName = function(unit) if unit == "player" then return mock.player.name end end
  UnitClass = function(unit)
    if unit == "player" then
      local c = mock.player.classFile
      return c:sub(1, 1) .. c:sub(2):lower(), c
    end
  end
  UnitLevel = function(unit) if unit == "player" then return mock.player.level end end
  GetRealmName = function() return mock.player.realm end
  UISpecialFrames = {}
  Enum = {
    WeeklyRewardChestThresholdType = { Activities = 1, RankedPvP = 2, Raid = 3, World = 6 },
    BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 },
  }
  ITEM_UPGRADE_TOOLTIP_FORMAT_STRING = "Upgrade Level: %s %d/%d"
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    mock.printed[#mock.printed + 1] = table.concat(parts, " ")
  end
end

-- Move the clock forward, running due timers in (due, creation) order.
function mock.advance(seconds)
  local target = mock.now + seconds
  while true do
    local best, bi
    for i, t in ipairs(timers) do
      if t.due <= target and (not best or t.due < best.due or (t.due == best.due and t.seq < best.seq)) then
        best, bi = t, i
      end
    end
    if not best then break end
    table.remove(timers, bi)
    if best.due > mock.now then mock.now = best.due end
    best.fn()
  end
  mock.now = target
end

function mock.fire(event, ...)
  local snapshot = {}
  for i, f in ipairs(frames) do snapshot[i] = f end
  for _, f in ipairs(snapshot) do
    local s = state[f]
    local handler = s.events[event] and s.scripts.OnEvent
    if handler then handler(f, event, ...) end
  end
end

mock.reset()
return mock
