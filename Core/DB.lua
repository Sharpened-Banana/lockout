local _, ns = ...

local DB = {}
ns.DB = DB

DB.SCHEMA = 2
DB.migrations = {} -- migrations[n] upgrades schema n-1 -> n

-- Other raids moved from opt-in Raids columns to their own tab.
DB.migrations[2] = function(db) db.settings.showLegacy = nil end

local function defaults()
  return {
    minLevel = 10,
    minimap = { hide = false },
    scale = 1.0,
    window = {},
    favorites = {},
    currentRealmOnly = false,
    sortKey = "ilvl",
    sortDesc = true,
  }
end

-- Copy keys from `src` into `dst` where `dst` has none; recurse into tables both sides hold.
local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = v
    elseif type(v) == "table" and type(dst[k]) == "table" then
      fill(dst[k], v)
    end
  end
end

function DB:Init(saved)
  local db = saved or { schema = self.SCHEMA }
  db.characters = db.characters or {}
  db.settings = db.settings or {}

  local from = db.schema or 1
  for n = from + 1, self.SCHEMA do
    local migrate = self.migrations[n]
    if migrate then migrate(db) end
    db.schema = n
  end
  db.schema = db.schema or self.SCHEMA

  fill(db.settings, defaults())
  LockoutDB = db
  ns.db = db
  return db
end

local SECTIONS = { "meta", "instances", "worldBosses", "vault", "mythicPlus", "delves", "equipment", "bags", "watchlist", "legacyBosses" }

function DB.Current()
  local guid = UnitGUID("player")
  local chars = ns.db.characters
  local rec = chars[guid]
  if not rec then
    rec = {}
    chars[guid] = rec
  end
  for _, key in ipairs(SECTIONS) do
    if type(rec[key]) ~= "table" then rec[key] = {} end
  end
  rec.bags.counts = rec.bags.counts or {}
  rec.delves.currencies = rec.delves.currencies or {}
  rec.vault.activities = rec.vault.activities or {}
  return rec
end

function DB.Forget(_, guid)
  if guid == UnitGUID("player") or not ns.db.characters[guid] then return false end
  ns.db.characters[guid] = nil
  ns.db.settings.favorites[guid] = nil
  ns.Fire("DATA_UPDATED")
  return true
end
