local _, ns = ...

-- Raids outside the current season, one row each, with the listed characters as columns.
-- A tab with Rows lists its own rows; ctx.characters holds the filtered, sorted character rows.
local Reset, Theme, Rows, Util = ns.Reset, ns.Theme, ns.Rows, ns.Util

local Legacy = { title = "Legacy", order = 5, rowHeader = "Raid" }
ns.Tabs.Legacy = Legacy

function Legacy.Rows(ctx)
  local seen = {}
  for _, raid in ipairs(ctx.season and ctx.season.raids or {}) do seen[raid.mapID] = true end

  local rows = {}
  for _, charRow in ipairs(ctx.characters or {}) do
    for _, inst in pairs(Reset.Active(charRow.char and charRow.char.instances, ctx.now)) do
      if inst.isRaid and inst.mapID and not seen[inst.mapID] then
        seen[inst.mapID] = true
        rows[#rows + 1] = { kind = "raid", key = inst.mapID, label = inst.name or tostring(inst.mapID) }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.label ~= b.label then return a.label < b.label end
    return a.key < b.key
  end)

  local out = {}
  if #rows > 0 then
    out[1] = { heading = true, key = "h:raids", label = "Raids" }
    for _, row in ipairs(rows) do out[#out + 1] = row end
  end
  local bosses = ns.Content.LEGACY_WORLD_BOSSES or {}
  if #bosses > 0 then
    out[#out + 1] = { heading = true, key = "h:bosses", label = "World bosses" }
    for _, boss in ipairs(bosses) do
      out[#out + 1] = { kind = "boss", key = boss.key, label = boss.name, boss = boss }
    end
  end
  return out
end

function Legacy.Columns(ctx)
  local cols = {}
  for _, charRow in ipairs(ctx.characters or {}) do
    local meta = charRow.char and charRow.char.meta or {}
    cols[#cols + 1] = {
      key = charRow.guid, guid = charRow.guid, char = charRow.char, label = charRow.label,
      color = { Theme.ClassColor(meta.classFile) }, width = 90,
    }
  end
  return cols
end

local function bossCell(boss, col, ctx)
  local kill = Reset.Active(col.char and col.char.legacyBosses, ctx.now)[boss.key]
  local tooltip = {}
  if boss.drop then tooltip[#tooltip + 1] = { left = boss.drop } end
  if kill then
    tooltip[#tooltip + 1] = { left = boss.name, right = "resets in " .. Util.Duration(kill.resetAt - ctx.now) }
  end
  return {
    text = kill and Theme.Icon.check or Rows.EMPTY,
    color = kill and Rows.COLORS.green or nil,
    title = boss.name,
    tooltip = #tooltip > 0 and tooltip or nil,
  }
end

function Legacy.Cell(row, col, ctx)
  if row.heading then return { text = "" } end
  if row.kind == "boss" then return bossCell(row.boss, col, ctx) end
  local cell = ns.Tabs.Raids.LockoutCell(col.char, row.key, ctx)
  cell.title = row.label
  return cell
end
