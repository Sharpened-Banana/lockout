local _, ns = ...

-- Raids outside the current season, one row each, with the listed characters as columns.
-- A tab with Rows lists its own rows; ctx.characters holds the filtered, sorted character rows.
local Reset, Theme = ns.Reset, ns.Theme

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
        rows[#rows + 1] = { key = inst.mapID, label = inst.name or tostring(inst.mapID) }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.label ~= b.label then return a.label < b.label end
    return a.key < b.key
  end)
  return rows
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

function Legacy.Cell(row, col, ctx)
  local cell = ns.Tabs.Raids.LockoutCell(col.char, row.key, ctx)
  cell.title = row.label
  return cell
end
