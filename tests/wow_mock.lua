-- Minimal World of Warcraft API mock for headless tests.
local mock = {}

local timers, frames, seq

local function newPlayer()
  return { guid = "Player-1-0001", name = "Thrall", realm = "Draenor", classFile = "SHAMAN", level = 80 }
end

-- Universal stub frame: unknown methods are no-ops returning the frame. Only method-style
-- (capitalized) keys get one, so an unset field such as `frame.link` reads nil as in the client.
local frameMethods = {}
local frameMeta = {}
frameMeta.__index = function(self, key)
  local m = frameMethods[key]
  if m then return m end
  if type(key) ~= "string" or not key:match("^%u") then return nil end
  local noop = function() return self end
  return noop
end

local state = setmetatable({}, { __mode = "k" }) -- frame -> { events, scripts, props, points }

function frameMethods.RegisterEvent(self, event) state[self].events[event] = true end
function frameMethods.UnregisterEvent(self, event) state[self].events[event] = nil end
function frameMethods.SetScript(self, name, fn) state[self].scripts[name] = fn end
function frameMethods.GetScript(self, name) return state[self].scripts[name] end

-- Real visibility (frames start shown, as in the client); scripts are not fired.
function frameMethods.Show(self) state[self].props.shown = true end
function frameMethods.Hide(self) state[self].props.shown = false end
function frameMethods.IsShown(self) return state[self].props.shown end
function frameMethods.SetShown(self, shown) state[self].props.shown = shown and true or false end

-- Simple stored properties: SetX(v) / GetX() -> v or the default.
local function property(name, default)
  frameMethods["Set" .. name] = function(self, v) state[self].props[name] = v end
  frameMethods["Get" .. name] = function(self)
    local v = state[self].props[name]
    if v == nil then return default end
    return v
  end
end
property("Text", "")
property("Width", 0)
property("Height", 0)
property("Value", 0)
property("Checked", false)
property("Scale", 1)
property("HorizontalScroll", 0)
property("VerticalScroll", 0)
property("Texture", nil)

function frameMethods.SetSize(self, w, h)
  self:SetWidth(w)
  self:SetHeight(h)
end
function frameMethods.GetSize(self) return self:GetWidth(), self:GetHeight() end
function frameMethods.SetTexCoord(self, ...) state[self].props.texCoord = { ... } end
function frameMethods.GetTexCoord(self) return unpack(state[self].props.texCoord or { 0, 1, 0, 1 }) end
function frameMethods.SetTextColor(self, r, g, b) state[self].props.textColor = { r, g, b } end
function frameMethods.GetTextColor(self) return unpack(state[self].props.textColor or { 1, 1, 1 }) end
function frameMethods.SetMinMaxValues(self, lo, hi) state[self].props.minMax = { lo, hi } end
function frameMethods.GetMinMaxValues(self)
  local mm = state[self].props.minMax or { 0, 0 }
  return mm[1], mm[2]
end
function frameMethods.SetPoint(self, ...) table.insert(state[self].points, { ... }) end
function frameMethods.ClearAllPoints(self) state[self].points = {} end
function frameMethods.GetNumPoints(self) return #state[self].points end
function frameMethods.GetPoint(self, i)
  local p = state[self].points[i or 1]
  if p then return unpack(p) end
end

local function newStub()
  local f = setmetatable({}, frameMeta)
  state[f] = { events = {}, scripts = {}, props = { shown = true }, points = {} }
  return f
end

-- Regions are distinct stubs so their text/size/visibility don't leak into the owner.
function frameMethods.CreateFontString() return newStub() end
function frameMethods.CreateTexture() return newStub() end

-- CreateFrame(type, name, ...) also sets the named global, as the client does.
local function createFrame(_, name)
  local f = newStub()
  frames[#frames + 1] = f
  if name then _G[name] = f end
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
