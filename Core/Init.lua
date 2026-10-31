local addonName, ns = ...

-- Logging ---------------------------------------------------------------

ns.log = {}
local logged = {}

function ns.Log(fmt, ...)
  ns.log[#ns.log + 1] = string.format(fmt, ...)
end

function ns.LogOnce(key, fmt, ...)
  if logged[key] then return end
  logged[key] = true
  ns.Log(fmt, ...)
end

-- Internal callbacks ----------------------------------------------------

local listeners = {}

function ns.On(name, fn)
  local list = listeners[name]
  if not list then
    list = {}
    listeners[name] = list
  end
  list[#list + 1] = fn
end

function ns.Fire(name, ...)
  local list = listeners[name]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then ns.LogOnce("callback:" .. name .. ":" .. i, "%s callback failed: %s", name, err) end
  end
end

-- Collector bus ---------------------------------------------------------

ns.collectors = {}
ns.deferred = {}

local order = {}   -- registration order, for deterministic dispatch
local pending = {} -- name -> true while a debounce timer is outstanding
local frame

local function resolve(path)
  local v = _G
  for part in path:gmatch("[^.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

function ns.RegisterCollector(def)
  def.debounce = def.debounce or 0.5
  if not ns.collectors[def.name] then order[#order + 1] = def.name end
  ns.collectors[def.name] = def
  def.disabled = nil
  for _, path in ipairs(def.requires or {}) do
    if resolve(path) == nil then
      def.disabled = true
      ns.Log("%s disabled: missing %s", def.name, path)
      return def
    end
  end
  for _, event in ipairs(def.events or {}) do frame:RegisterEvent(event) end
  return def
end

local function run(name)
  local def = ns.collectors[name]
  if not def or def.disabled then return end
  if InCombatLockdown() then
    ns.deferred[name] = true
    return
  end
  ns.deferred[name] = nil
  local ok, err = pcall(function() return def.Collect(def, ns.DB:Current(), time()) end)
  if not ok then
    ns.LogOnce(name, "%s failed: %s", name, err)
    return
  end
  ns.Fire("DATA_UPDATED", name)
end

ns.CollectNow = run

function ns.Schedule(name)
  local def = ns.collectors[name]
  if not def or def.disabled or pending[name] then return end
  pending[name] = true
  C_Timer.After(def.debounce, function()
    pending[name] = nil
    run(name)
  end)
end

local function listens(def, event)
  for _, e in ipairs(def.events or {}) do
    if e == event then return true end
  end
  return false
end

local function onEvent(_, event, ...)
  if event == "ADDON_LOADED" then
    if (...) == addonName then
      ns.DB:Init(LockoutDB)
      ns.Fire("DB_READY")
    end
    return
  end
  if event == "PLAYER_LOGIN" then
    for _, name in ipairs(order) do
      local def = ns.collectors[name]
      if not def.disabled then
        if def.OnLogin then
          local ok, err = pcall(def.OnLogin)
          if not ok then ns.LogOnce(name .. ":login", "%s OnLogin failed: %s", name, err) end
        end
        ns.Schedule(name)
      end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    for _, name in ipairs(order) do
      if ns.deferred[name] then
        ns.deferred[name] = nil
        ns.Schedule(name)
      end
    end
  end
  for _, name in ipairs(order) do
    local def = ns.collectors[name]
    if not def.disabled and listens(def, event) then
      if def.OnEvent then
        local ok, err = pcall(def.OnEvent, event, ...)
        if not ok then ns.LogOnce(name .. ":event", "%s OnEvent failed: %s", name, err) end
      end
      ns.Schedule(name)
    end
  end
end

frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", onEvent)

-- Slash commands --------------------------------------------------------

local slash = {}

function ns.RegisterSlash(sub, fn)
  slash[sub] = fn
end

SLASH_LOCKOUT1 = "/lockout"
SLASH_LOCKOUT2 = "/lo"
SlashCmdList = SlashCmdList or {}
SlashCmdList.LOCKOUT = function(msg)
  local sub, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local fn = slash[sub:lower()]
  if fn then
    fn(rest)
    return
  end
  local subs = {}
  for k in pairs(slash) do
    if k ~= "" then subs[#subs + 1] = k end
  end
  table.sort(subs)
  print("|cff33ff99Lockout|r usage: /lockout [" .. table.concat(subs, "|") .. "]")
end

ns.RegisterSlash("debug", function()
  if #ns.log == 0 then
    print("|cff33ff99Lockout|r log is empty")
    return
  end
  for _, line in ipairs(ns.log) do
    print("|cff33ff99Lockout|r " .. line)
  end
end)
