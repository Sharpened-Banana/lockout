local _, ns = ...

local Content, Util = ns.Content, ns.Util

local function isEnchantable(slot, link)
  if Content.ENCHANT_SLOTS[slot] then return true end
  if slot == 17 then
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
  end
  return false
end

local function emptySockets(link, gems)
  local total = 0
  for key, count in pairs(C_Item.GetItemStats(link) or {}) do
    if key:find("^EMPTY_SOCKET_") then total = total + count end
  end
  local filled = 0
  for _, gem in ipairs(gems) do
    if gem ~= 0 then filled = filled + 1 end
  end
  return math.max(0, total - filled)
end

-- Upgrade track from the item tooltip, e.g. "Upgrade Level: Hero 4/6".
local function upgradeTrack(slot, pattern)
  local data = C_TooltipInfo.GetInventoryItem("player", slot)
  if not data or not data.lines then return nil end
  for _, line in ipairs(data.lines) do
    local track, cur, max = (line.leftText or ""):match(pattern)
    if track then return track, tonumber(cur), tonumber(max) end
  end
end

ns.RegisterCollector({
  name = "Equipment",
  events = { "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" },
  requires = {
    "C_TooltipInfo.GetInventoryItem", "C_Item.GetDetailedItemLevelInfo",
    "C_Item.GetItemInfoInstant", "C_Item.GetItemStats",
  },

  Collect = function(_, record)
    record.equipment = record.equipment or {}
    local pattern = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING and Util.FormatToPattern(ITEM_UPGRADE_TOOLTIP_FORMAT_STRING)
    for _, slot in ipairs(Content.EQUIP_SLOTS) do
      local link = GetInventoryItemLink("player", slot)
      local parsed = link and Util.ParseItemLink(link)
      if parsed then
        local track, trackCur, trackMax
        if pattern then track, trackCur, trackMax = upgradeTrack(slot, pattern) end
        record.equipment[slot] = {
          link = link,
          itemID = parsed.itemID,
          ilvl = C_Item.GetDetailedItemLevelInfo(link), -- nil until item data is cached
          track = track,
          trackCur = trackCur,
          trackMax = trackMax,
          missingEnchant = isEnchantable(slot, link) and parsed.enchantID == 0,
          emptySockets = emptySockets(link, parsed.gems),
        }
      else
        record.equipment[slot] = nil
      end
    end
  end,
})
