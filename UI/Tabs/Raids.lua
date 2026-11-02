local _, ns = ...

local Rows, Reset, Util = ns.Rows, ns.Reset, ns.Util

-- Known difficulties in display order: LFR, Normal, Heroic, Mythic.
local KNOWN = { { id = 17, letter = "L" }, { id = 14, letter = "N" }, { id = 15, letter = "H" }, { id = 16, letter = "M" } }
local KNOWN_RANK = {}
for i, d in ipairs(KNOWN) do KNOWN_RANK[d.id] = i end

local function letterOf(inst)
  local rank = KNOWN_RANK[inst.difficultyID]
  if rank then return KNOWN[rank].letter end
  return (inst.difficultyName or "?"):sub(1, 1)
end

-- Known difficulties first (LFR..Mythic), then any others by id.
local function byDifficulty(a, b)
  local ra, rb = KNOWN_RANK[a.difficultyID] or 100, KNOWN_RANK[b.difficultyID] or 100
  if ra ~= rb then return ra < rb end
  return (a.difficultyID or 0) < (b.difficultyID or 0)
end

local function isFull(inst)
  return (inst.total or 0) > 0 and (inst.killed or 0) >= inst.total
end

local Raids = { title = "Raids", order = 1 }
ns.Tabs.Raids = Raids

function Raids.Columns(ctx)
  local cols = {}
  for _, raid in ipairs(ctx.season and ctx.season.raids or {}) do
    cols[#cols + 1] = { key = raid.mapID, label = raid.name, width = 110 }
  end
  return cols
end

-- One character's active lockouts for one raid map; the Legacy tab shares it.
function Raids.LockoutCell(char, mapID, ctx)
  local shown = {}
  for _, inst in pairs(Reset.Active(char and char.instances, ctx.now)) do
    if inst.mapID == mapID and inst.difficultyID then shown[#shown + 1] = inst end
  end
  if #shown == 0 then return { text = Rows.EMPTY } end
  table.sort(shown, byDifficulty)

  local badges, tooltip = {}, {}
  for _, inst in ipairs(shown) do
    badges[#badges + 1] = letterOf(inst) .. " " .. (inst.killed or 0) .. "/" .. (inst.total or 0)
    local right = inst.resetAt and ("resets in " .. Util.Duration(inst.resetAt - ctx.now)) or nil
    tooltip[#tooltip + 1] = { left = inst.difficultyName or letterOf(inst), right = right, color = Rows.COLORS.yellow }
    for _, boss in ipairs(inst.encounters or {}) do
      tooltip[#tooltip + 1] = {
        left = boss.name or "?",
        right = boss.killed and "Killed" or "Alive",
        color = boss.killed and Rows.COLORS.green or nil,
      }
    end
  end

  local color = isFull(shown[#shown]) and Rows.COLORS.green or Rows.COLORS.yellow
  return { text = table.concat(badges, "  "), color = color, tooltip = tooltip }
end

function Raids.Cell(char, col, ctx)
  return Raids.LockoutCell(char, col.key, ctx)
end
