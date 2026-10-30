local _, ns = ...

local Rows, Reset, Util = ns.Rows, ns.Reset, ns.Util

local MYTHIC_ZERO = 23

local Dungeons = { title = "Dungeons", order = 2 }
ns.Tabs.Dungeons = Dungeons

function Dungeons.Columns(ctx)
  local cols = {}
  for _, dungeon in ipairs(ctx.season and ctx.season.dungeons or {}) do
    cols[#cols + 1] = { key = dungeon.mapID, label = dungeon.name, width = 90 }
  end
  return cols
end

-- Season best for the M+ map that shares this dungeon's map ID.
local function seasonBest(char, mapID, ctx)
  for _, m in ipairs(ctx.season and ctx.season.mplus or {}) do
    if m.mapID == mapID then
      local best = Reset.MythicPlus(char.mythicPlus, ctx.now).seasonBest[m.challengeMapID]
      return best and best > 0 and best or nil
    end
  end
  return nil
end

function Dungeons.Cell(char, col, ctx)
  local m0 = Reset.Active(char.instances, ctx.now)[col.key .. ":" .. MYTHIC_ZERO]
  local best = seasonBest(char, col.key, ctx)

  local parts, tooltip = {}, {}
  if m0 then
    parts[#parts + 1] = "✓"
    local right = m0.resetAt and ("resets in " .. Util.Duration(m0.resetAt - ctx.now)) or nil
    tooltip[#tooltip + 1] = { left = "Mythic 0", right = right }
  end
  if best then
    parts[#parts + 1] = "+" .. best
    tooltip[#tooltip + 1] = { left = "Season best", right = "+" .. best }
  end
  if #parts == 0 then return { text = Rows.EMPTY } end
  return { text = table.concat(parts, " "), tooltip = tooltip }
end
