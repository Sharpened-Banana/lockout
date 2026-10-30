local _, ns = ...

local Rows, Reset, Util = ns.Rows, ns.Reset, ns.Util

local WorldBosses = { title = "World Bosses", order = 3 }
ns.Tabs.WorldBosses = WorldBosses

local function isBossKey(key)
  return type(key) == "string" and (key:find("^wb") ~= nil or key:find("^q") ~= nil)
end

-- Configured bosses first, then any boss key seen on a character (label from the stored name).
function WorldBosses.Columns(ctx)
  local cols, seen = {}, {}
  for _, boss in ipairs(ns.Content.WORLD_BOSSES) do
    if not seen[boss.key] then
      seen[boss.key] = true
      cols[#cols + 1] = { key = boss.key, label = boss.name, width = 80 }
    end
  end

  local extra = {}
  for _, char in pairs(ctx.db.characters or {}) do
    for key, boss in pairs(Reset.Active(char.worldBosses, ctx.now)) do
      if isBossKey(key) then
        local existing = extra[key]
        local label = boss.name or key
        -- Pick the same label no matter which character is visited first.
        if not seen[key] and (existing == nil or label < existing.label) then
          extra[key] = { key = key, label = label, width = 80 }
        end
      end
    end
  end
  local list = {}
  for _, col in pairs(extra) do list[#list + 1] = col end
  table.sort(list, function(a, b)
    if a.label ~= b.label then return a.label < b.label end
    return a.key < b.key
  end)
  for _, col in ipairs(list) do cols[#cols + 1] = col end
  return cols
end

function WorldBosses.Cell(char, col, ctx)
  local boss = Reset.Active(char.worldBosses, ctx.now)[col.key]
  if not boss then return { text = Rows.EMPTY } end
  local tooltip
  if boss.resetAt then
    tooltip = { { left = boss.name or col.label or col.key, right = "resets in " .. Util.Duration(boss.resetAt - ctx.now) } }
  end
  return { text = "✓", color = Rows.COLORS.green, tooltip = tooltip }
end
