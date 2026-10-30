local _, ns = ...

local Rows, Reset, Util = ns.Rows, ns.Reset, ns.Util

local Weekly = { title = "Weekly", order = 4 }
ns.Tabs.Weekly = Weekly

local VAULT_SLOTS = 3

local VAULT_COLUMNS = {
  vaultRaid = { label = "Raid", chest = "Raid" },
  vaultDungeons = { label = "Dungeons", chest = "Activities" },
  vaultWorld = { label = "World", chest = "World" },
}

function Weekly.Columns()
  return {
    { key = "vaultRaid", label = "Raid", width = 80 },
    { key = "vaultDungeons", label = "Dungeons", width = 80 },
    { key = "vaultWorld", label = "World", width = 80 },
    { key = "key", label = "Key", width = 130 },
    { key = "rating", label = "Rating", width = 60 },
    { key = "delves", label = "Delves", width = 90 },
    { key = "ready", label = "Vault", width = 50 },
  }
end

local function vaultCell(char, chest, ctx)
  local wanted = Enum.WeeklyRewardChestThresholdType[chest]
  local slots = {}
  for _, a in ipairs(Reset.Vault(char.vault, ctx.now).activities) do
    if a.type == wanted then slots[#slots + 1] = a end
  end
  if #slots == 0 then return { text = Rows.EMPTY } end
  table.sort(slots, function(a, b) return (a.index or 0) < (b.index or 0) end)

  local unlocked, bestIlvl, tooltip = 0, 0, {}
  for i, a in ipairs(slots) do
    local progress, threshold = a.progress or 0, a.threshold or 0
    if threshold > 0 and progress >= threshold then unlocked = unlocked + 1 end
    local right = math.min(progress, threshold) .. "/" .. threshold
    if a.rewardIlvl and a.rewardIlvl > 0 then
      bestIlvl = math.max(bestIlvl, a.rewardIlvl)
      right = right .. " · " .. a.rewardIlvl
    end
    tooltip[i] = { left = "Slot " .. (a.index or i), right = right }
  end

  local text = unlocked .. "/" .. VAULT_SLOTS
  if bestIlvl > 0 then text = text .. " · " .. bestIlvl end
  return { text = text, color = unlocked == VAULT_SLOTS and Rows.COLORS.green or nil, tooltip = tooltip }
end

local function keyCell(char, ctx)
  local key = Reset.MythicPlus(char.mythicPlus, ctx.now).key
  if not key or not key.level then return { text = Rows.EMPTY } end
  local name
  for _, m in ipairs(ctx.season and ctx.season.mplus or {}) do
    if m.challengeMapID == key.challengeMapID then name = m.name end
  end
  return { text = "+" .. key.level .. (name and (" " .. name) or "") }
end

local function ratingCell(char, ctx)
  local mp = Reset.MythicPlus(char.mythicPlus, ctx.now)
  if mp.rating <= 0 then return { text = Rows.EMPTY } end
  local tooltip
  if mp.weeklyBest > 0 then
    tooltip = { { left = "Weekly best", right = "+" .. mp.weeklyBest } }
  end
  return { text = tostring(math.floor(mp.rating + 0.5)), tooltip = tooltip }
end

-- Delve currencies never expire; the tooltip says how old the snapshot is.
local function delvesCell(char, ctx)
  local delves = char.delves or {}
  local owned = delves.currencies or {}
  local qtys, tooltip = {}, {}
  for _, currency in ipairs(ns.Content.DELVE_CURRENCIES) do
    local qty = owned[currency.id]
    if qty then
      qtys[#qtys + 1] = tostring(qty)
      tooltip[#tooltip + 1] = { left = currency.name, right = tostring(qty) }
    end
  end
  if #qtys == 0 then return { text = Rows.EMPTY } end
  if delves.updatedAt then
    tooltip[#tooltip + 1] = { left = "updated " .. Util.Age(ctx.now - delves.updatedAt) }
  end
  return { text = table.concat(qtys, " / "), tooltip = tooltip }
end

local function readyCell(char, ctx)
  if not Reset.Vault(char.vault, ctx.now).ready then return { text = Rows.EMPTY } end
  return { text = "🎁", tooltip = { { left = "Great Vault reward waiting" } } }
end

function Weekly.Cell(char, col, ctx)
  local vault = VAULT_COLUMNS[col.key]
  if vault then return vaultCell(char, vault.chest, ctx) end
  if col.key == "key" then return keyCell(char, ctx) end
  if col.key == "rating" then return ratingCell(char, ctx) end
  if col.key == "delves" then return delvesCell(char, ctx) end
  if col.key == "ready" then return readyCell(char, ctx) end
  return { text = Rows.EMPTY }
end
