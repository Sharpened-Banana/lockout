local _, ns = ...

-- Pure: ordered character rows from the db and the active filters.
local Rows = {}
ns.Rows = Rows

ns.Tabs = ns.Tabs or {}
ns.TabOrder = { "Raids", "Dungeons", "WorldBosses", "Weekly" }

-- Cell text when there is nothing to show.
Rows.EMPTY = "–"

-- Shared cell colors ({r, g, b}).
Rows.COLORS = {
  green = { 0.3, 0.9, 0.3 },
  yellow = { 1, 0.82, 0 },
}

local function metaOf(char)
  return char and char.meta or {}
end

local function nameOf(char)
  return metaOf(char).name or ""
end

-- opts: minLevel, filter, realmOnly, realm, favorites, sortKey ("name"|"level"|"ilvl"), sortDesc
function Rows.Build(db, opts)
  opts = opts or {}
  local current = UnitGUID("player")
  local needle = opts.filter and opts.filter ~= "" and opts.filter:lower() or nil
  local favorites = opts.favorites or {}

  local rows = {}
  for guid, char in pairs(db.characters or {}) do
    local meta = metaOf(char)
    local keep = true
    if opts.minLevel and guid ~= current and (meta.level or 0) < opts.minLevel then keep = false end
    if keep and opts.realmOnly and meta.realm ~= opts.realm then keep = false end
    if keep and needle and not nameOf(char):lower():find(needle, 1, true) then keep = false end
    if keep then rows[#rows + 1] = { guid = guid, char = char, label = nameOf(char) } end
  end

  -- Same name on several included rows: show Name-Realm.
  local counts = {}
  for _, row in ipairs(rows) do counts[row.label] = (counts[row.label] or 0) + 1 end
  for _, row in ipairs(rows) do
    if row.label ~= "" and counts[row.label] > 1 then row.label = row.label .. "-" .. (metaOf(row.char).realm or "?") end
  end

  local sortKey, desc = opts.sortKey, opts.sortDesc
  table.sort(rows, function(a, b)
    local fa, fb = favorites[a.guid] and true or false, favorites[b.guid] and true or false
    if fa ~= fb then return fa end
    local ma, mb = metaOf(a.char), metaOf(b.char)
    local na, nb = nameOf(a.char):lower(), nameOf(b.char):lower()
    local va, vb
    if sortKey == "level" then
      va, vb = ma.level or 0, mb.level or 0
    elseif sortKey == "ilvl" then
      va, vb = ma.ilvl or 0, mb.ilvl or 0
    else
      va, vb = na, nb
    end
    if va ~= vb then
      if desc then return va > vb end
      return va < vb
    end
    if na ~= nb then return na < nb end
    return a.guid < b.guid
  end)
  return rows
end
