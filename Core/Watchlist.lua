local _, ns = ...

-- Pure watchlist logic. ns.Consumables is read at call time (Data/ loads after Core/).
local Watchlist = {}
ns.Watchlist = Watchlist

function Watchlist.IsDefault(itemID)
  return ns.Consumables.items[itemID] ~= nil
end

-- watchlist[itemID]: true = shown, false = hidden, nil = shown iff default.
function Watchlist.IsShown(char, itemID)
  local v = char.watchlist and char.watchlist[itemID]
  if v == nil then return Watchlist.IsDefault(itemID) end
  return v
end

function Watchlist.Set(char, itemID, on)
  char.watchlist = char.watchlist or {}
  if not on then
    char.watchlist[itemID] = false
  elseif Watchlist.IsDefault(itemID) then
    char.watchlist[itemID] = nil
  else
    char.watchlist[itemID] = true
  end
end

function Watchlist.ScanSet(db)
  local set = {}
  for id in pairs(ns.Consumables.items) do set[id] = true end
  for _, char in pairs(db.characters or {}) do
    -- Switched-off items stay scanned: they remain listed for editing and keep their counts.
    for id in pairs(char.watchlist or {}) do set[id] = true end
  end
  return set
end

function Watchlist.Groups(char, db, editing)
  local counts = char.bags and char.bags.counts or {}
  local byCategory = {}
  for id in pairs(Watchlist.ScanSet(db)) do
    local shown = Watchlist.IsShown(char, id)
    if editing or shown then
      local category = ns.Consumables.CategoryOf(id)
      local list = byCategory[category]
      if not list then
        list = {}
        byCategory[category] = list
      end
      list[#list + 1] = { itemID = id, count = counts[id] or 0, shown = shown }
    end
  end

  -- A category outside CATEGORIES (stale data) falls back to Other so nothing is dropped.
  local known = {}
  for _, name in ipairs(ns.Consumables.CATEGORIES) do known[name] = true end
  local other = byCategory.Other or {}
  for category, list in pairs(byCategory) do
    if category ~= "Other" and not known[category] then
      for _, item in ipairs(list) do other[#other + 1] = item end
      byCategory[category] = nil
    end
  end
  byCategory.Other = #other > 0 and other or nil

  local groups = {}
  local function add(category)
    local list = byCategory[category]
    if not list or #list == 0 then return end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    groups[#groups + 1] = { category = category, items = list }
  end
  for _, category in ipairs(ns.Consumables.CATEGORIES) do add(category) end
  add("Other")
  return groups
end
