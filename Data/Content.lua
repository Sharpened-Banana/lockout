local _, ns = ...

local Content = {}
ns.Content = Content

-- Display order: head, neck, shoulder, back, chest, wrist, hands, waist, legs, feet, rings, trinkets, weapons.
Content.EQUIP_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }

-- Blizzard global string names (localized) with English fallback.
local SLOT_GLOBALS = {
  [1] = { "HEADSLOT", "Head" },
  [2] = { "NECKSLOT", "Neck" },
  [3] = { "SHOULDERSLOT", "Shoulder" },
  [15] = { "BACKSLOT", "Back" },
  [5] = { "CHESTSLOT", "Chest" },
  [9] = { "WRISTSLOT", "Wrist" },
  [10] = { "HANDSSLOT", "Hands" },
  [6] = { "WAISTSLOT", "Waist" },
  [7] = { "LEGSSLOT", "Legs" },
  [8] = { "FEETSLOT", "Feet" },
  [11] = { "FINGER0SLOT", "Ring 1" },
  [12] = { "FINGER1SLOT", "Ring 2" },
  [13] = { "TRINKET0SLOT", "Trinket 1" },
  [14] = { "TRINKET1SLOT", "Trinket 2" },
  [16] = { "MAINHANDSLOT", "Main Hand" },
  [17] = { "SECONDARYHANDSLOT", "Off Hand" },
}
Content.SLOT_NAMES = {}
for slot, g in pairs(SLOT_GLOBALS) do
  Content.SLOT_NAMES[slot] = _G[g[1]] or g[2]
end

-- Slots that take an enchant. Off-hand (17) is handled in code: enchantable only when it holds a weapon.
-- verify in game: Midnight enchantable slots
Content.ENCHANT_SLOTS = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true, [11] = true, [12] = true, [16] = true }

-- Weekly world-boss quests, one per boss. Shape: { key = "q<questID>", questID = n, name = "..." }
-- needs IDs (patch 12.0.7)
Content.WORLD_BOSSES = {}

-- Old world bosses worth farming, shown on the Legacy tab. Shape: { key = "q<questID>", questID = n, name = "...", drop = "..." or nil }
-- questID is each boss's hidden weekly loot-lockout quest ("Short-Supply Reward"), cross-checked against SavedInstances' WorldBoss.lua.
-- Ordered by expansion, then name.
Content.LEGACY_WORLD_BOSSES = {
  -- Mists of Pandaria
  { key = "q32098", questID = 32098, name = "Galleon", drop = "Son of Galleon" }, -- Galleon
  { key = "q32518", questID = 32518, name = "Nalak", drop = "Thundering Cobalt Cloud Serpent" }, -- Nalak
  { key = "q32519", questID = 32519, name = "Oondasta", drop = "Cobalt Primordial Direhorn" }, -- Oondasta
  { key = "q32099", questID = 32099, name = "Sha of Anger", drop = "Heavenly Onyx Cloud Serpent" }, -- Sha of Anger
  -- Warlords of Draenor
  { key = "q37464", questID = 37464, name = "Rukhmar", drop = "Solar Spirehawk" }, -- Rukhmar
}

-- Delve currencies (Restored Coffer Key equivalent, coffer key shards). Shape: { id = currencyID, name = "..." }
-- needs IDs (patch 12.0.7)
Content.DELVE_CURRENCIES = {}
