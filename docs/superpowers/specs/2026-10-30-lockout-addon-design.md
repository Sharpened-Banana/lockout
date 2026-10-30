# Lockout — Warband Lockout & Character Tracker (Design)

Date: 2026-10-30
Target: World of Warcraft Retail, Midnight (patch 12.0.7, `## Interface: 120007`)

## 1. Goal

A standalone addon window, in the spirit of Warband Nexus, that shows every
character in the player's warband side by side: what they are saved to, what
weekly progress they have, and — on click — their gear and consumables.

Success looks like: logging in on any character, opening one window, and
answering "who can still run X this week?", "who has a Vault to claim?",
"who forgot an enchant?" and "who is out of flasks?" without logging over.

### In scope
- Raid lockouts, per boss, per difficulty (LFR / Normal / Heroic / Mythic),
  including legacy raids the character is saved to.
- Mythic 0 dungeon lockouts.
- World boss weekly kills.
- Great Vault progress (Raid, Dungeons, World/Delves rows) and unclaimed rewards.
- Delve-related currencies (season-specific IDs in a data file).
- Mythic+: owned keystone, overall rating, weekly best, season best per dungeon.
- Character basics: name, realm, class, spec, level, ilvl (overall + equipped),
  gold, last seen.
- Equipment per slot: item, ilvl, upgrade track, missing enchant, empty sockets.
- Consumable counts in the character's **bags only** (backpack, bags, reagent
  bag), with a per-character watchlist.

### Out of scope
- Bank / Warband bank / reagent bank counts.
- Gold ledgers, currencies beyond delve currencies, reputations, professions.
- Cross-account sync, guild features, PvP.
- Reading data for characters that have never logged in with the addon
  enabled (the WoW API cannot do this; such characters simply don't appear).

## 2. Architecture

Plain Lua with a small internal module system. Embedded libraries only:
LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 (fetched via
`.pkgmeta` externals for the BigWigs packager; vendored copies in `Libs/` for
local development).

Data flow: **collectors → DB (SavedVariables) → UI**. The UI never calls game
APIs for character data; it renders only stored records, so the current
character and offline alts are displayed identically.

### File layout
```
Lockout/
  Lockout.toc
  embeds.xml
  .pkgmeta
  Libs/                      LibStub, CallbackHandler, LDB, LibDBIcon
  Core/
    Init.lua                 addon namespace, module registry, event bus
    DB.lua                   SavedVariables init, schema version, migrations,
                             current-character record access, forget character
    Reset.lua                pure expiry logic (now passed in)
    Watchlist.lua            pure watchlist resolution
  Data/
    Consumables.lua          curated default consumables, grouped by category
    Content.lua              season raids/dungeons, world boss quest IDs,
                             delve currency IDs, equipment slot list,
                             enchantable slots
  Collectors/
    Character.lua  Instances.lua  WorldBosses.lua  Vault.lua
    MythicPlus.lua Delves.lua     Equipment.lua    Bags.lua
  UI/
    Theme.lua                colors, fonts, backdrop helpers
    MainFrame.lua            window, tabs, filter bar, persistence, Esc-close
    Grid.lua                 generic virtualized row/column grid + sorting
    Tabs/Raids.lua  Tabs/Dungeons.lua  Tabs/WorldBosses.lua  Tabs/Weekly.lua
    DetailPanel.lua          character detail panel incl. watchlist editing
    Minimap.lua              LDB object + LibDBIcon button
    Settings.lua             Blizzard Settings panel
  tests/
    wow_mock.lua             minimal WoW API stubs
    *_spec.lua               busted specs
```

### Module & event bus
- `Init.lua` creates the namespace (`local _, ns = ...`) and a single event
  frame. Modules register with `ns:RegisterModule(name, module)`.
- Each collector declares `events = { ... }` and implements
  `Collect(record)`. The bus coalesces bursts (e.g. `BAG_UPDATE_DELAYED`,
  `UNIT_INVENTORY_CHANGED`) with a short debounce (≈0.5 s) per collector.
- Collection is deferred while `InCombatLockdown()` is true and runs on
  `PLAYER_REGEN_ENABLED`. This also keeps clear of Midnight's in-combat
  restrictions.
- After any collector writes, the bus fires an internal `LOCKOUT_DATA_UPDATED`
  callback; the UI refreshes if visible.

## 3. Collectors

| Collector | Source APIs | Triggers |
|---|---|---|
| Character | `UnitName`, `GetRealmName`, `UnitClass`, `UnitLevel`, `GetSpecialization`/`GetSpecializationInfo`, `GetAverageItemLevel`, `GetMoney` | `PLAYER_LOGIN`, `PLAYER_LEVEL_UP`, `PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_MONEY`, `PLAYER_EQUIPMENT_CHANGED` |
| Instances | `RequestRaidInfo`, `GetNumSavedInstances`, `GetSavedInstanceInfo`, `GetSavedInstanceEncounterInfo` | `PLAYER_LOGIN` (calls `RequestRaidInfo`), `UPDATE_INSTANCE_INFO`, `BOSS_KILL`, `ENCOUNTER_END` |
| WorldBosses | `GetNumSavedWorldBosses`, `GetSavedWorldBossInfo`, `C_QuestLog.IsQuestFlaggedCompleted` with quest IDs from `Data/Content.lua` | `UPDATE_INSTANCE_INFO`, `QUEST_TURNED_IN` |
| Vault | `C_WeeklyRewards.GetActivities`, `C_WeeklyRewards.HasAvailableRewards` | `PLAYER_LOGIN`, `WEEKLY_REWARDS_UPDATE` |
| MythicPlus | `C_MythicPlus.GetOwnedKeystoneChallengeMapID`, `C_MythicPlus.GetOwnedKeystoneLevel`, `C_ChallengeMode.GetOverallDungeonScore`, `C_MythicPlus.GetRunHistory`, `C_MythicPlus.GetSeasonBestForMap` | `PLAYER_LOGIN`, `CHALLENGE_MODE_COMPLETED`, `BAG_UPDATE_DELAYED` (key changes), `MYTHIC_PLUS_CURRENT_AFFIX_UPDATE` |
| Delves | `C_CurrencyInfo.GetCurrencyInfo` for IDs in `Data/Content.lua` | `PLAYER_LOGIN`, `CURRENCY_DISPLAY_UPDATE` |
| Equipment | `GetInventoryItemLink`, `C_Item.GetDetailedItemLevelInfo`, `C_TooltipInfo.GetInventoryItem` (upgrade track line), item link enchant field, `C_Item.GetItemStats` / gem fields for empty sockets | `PLAYER_LOGIN`, `PLAYER_EQUIPMENT_CHANGED` |
| Bags | `C_Container.GetContainerNumSlots`, `C_Container.GetContainerItemInfo` over backpack, bags 1–4 and the reagent bag | `PLAYER_LOGIN`, `BAG_UPDATE_DELAYED` |

Notes:
- Bags only counts item IDs in the **scan set**: the union of default
  consumables and every item any character has switched on. Counts for all
  scan-set items are stored even if switched off for this character.
- Upgrade track is parsed from the tooltip line matching the localized
  `ITEM_UPGRADE_TOOLTIP_FORMAT_STRING` pattern; if not found, track is `nil`.
- Missing enchant: slot is in the season's enchantable-slot list and the
  link's enchant field is empty.

### Error handling
- Every `Collect` call is wrapped in `pcall`. A failure logs once per session
  (visible via `/lockout debug`) and leaves the previous stored data intact;
  other collectors are unaffected.
- A collector whose required API is missing (`nil`) disables itself at load
  and logs why. This makes API changes in future patches degrade gracefully.

## 4. Data model

SavedVariables (account-wide): `LockoutDB`.

```lua
LockoutDB = {
  schema   = 1,
  settings = { minLevel = 10, minimap = { hide = false }, showLegacy = false,
               scale = 1.0, window = { point, x, y, w, h }, favorites = { [guid] = true },
               currentRealmOnly = false },
  characters = {
    [guid] = {
      meta        = { name, realm, classFile, level, specID, ilvl, ilvlEquipped,
                      gold, lastSeen },
      instances   = { ["<instanceID>:<difficultyID>"] = { name, instanceID,
                      difficultyID, difficultyName, isRaid, resetAt, extended,
                      killed, total, encounters = { { name, killed }, ... } } },
      worldBosses = { [bossKey] = { name, resetAt } },
      vault       = { resetAt, unclaimed, activities = { { type, index,
                      threshold, progress, level } } },
      mythicPlus  = { resetAt, key = { mapID, level }, rating, weeklyBest,
                      seasonBest = { [mapID] = level },
                      runs = { { mapID, level, completed } } },
      delves      = { resetAt, currencies = { [currencyID] = qty } },
      equipment   = { [slotID] = { link, itemID, ilvl, track, trackCur, trackMax,
                      missingEnchant, emptySockets } },
      bags        = { scannedAt, counts = { [itemID] = n } },
      watchlist   = { [itemID] = true | false },
    },
  },
}
```

- Key is the player GUID (stable across renames). `meta.lastSeen` is
  `time()` at last collection.
- `DB.lua` runs ordered migrations `migrations[n](db)` for `schema < CURRENT`.
- Characters below `settings.minLevel` are still stored but hidden in the UI.
- "Forget character" deletes `characters[guid]` after a confirmation popup
  (`StaticPopup`). The current character cannot be forgotten.

## 5. Reset handling (`Core/Reset.lua`)

All functions are pure and take `now` explicitly.

- On collection, relative timers become absolute: `resetAt = now + seconds`.
  - Instances/world bosses: `seconds` from the API's reset field.
  - Weekly data (vault, mythicPlus.weeklyBest/runs, delves, quest-based world
    bosses): `C_DateAndTime.GetSecondsUntilWeeklyReset()`.
- `Reset.IsExpired(entry, now)` → `now >= entry.resetAt`.
- Display rules:
  - Expired instance/world boss lockout → treated as not saved.
  - Extended lockouts use their own `resetAt` (the API reports it).
  - Expired vault: if any activity had `progress >= threshold`, the character
    is shown as **Vault ready** (unclaimed) until next collected; progress
    displays as 0.
  - `Collect` on the live character always overwrites with truth, clearing
    stale flags.
  - Non-resetting data (key, rating, gear, bags) is shown with an
    "updated <relative time>" hint.
- Region differences are handled implicitly because reset times come from the
  client API, never from a hard-coded schedule.

## 6. Watchlist (`Core/Watchlist.lua`)

- `IsShown(char, itemID)`:
  `char.watchlist[itemID] == true` → shown;
  `== false` → hidden;
  `nil` → shown iff `itemID` is in the default list.
- `ScanSet(db)`: default IDs ∪ every ID with `true` in any character's
  watchlist.
- Adding a custom item (drag-drop or item ID entry) sets `watchlist[id] = true`
  for that character and triggers a bag rescan if the item is new to the scan
  set. Custom items are grouped under "Other".
- Default list lives in `Data/Consumables.lua` as
  `{ category = "Flasks"|"Potions"|"Food"|"Runes"|"Oils", items = { itemID, ... } }`,
  covering all quality ranks of current-expansion consumables.

## 7. UI

### Main window
- Custom frame (`BackdropTemplate`), dark flat theme, class-colored names.
- Movable, resizable (min size enforced), position/size/scale persisted,
  registered in `UISpecialFrames` so `Esc` closes it.
- Opened by `/lockout` (alias `/lo`) or the minimap/LDB button.
- Header: tabs **Raids · Dungeons · World Bosses · Weekly**, name filter box,
  "current realm only" checkbox, settings cog.

### Grid (`UI/Grid.lua`)
- Generic component: frozen left column (character), scrollable columns,
  virtualized rows (row frames recycled), sortable headers.
- Row: favorite star, class-colored name, level, ilvl. Favorites pin to top;
  then the active sort (default: ilvl desc).
- Click row → open detail panel for that character.

### Tabs (each provides columns + cell renderer + tooltip)
- **Raids**: one column per current-season raid (from `Data/Content.lua`);
  with `showLegacy`, extra columns for any other raid any character is saved
  to. Cell: difficulty badges `L/N/H/M k/n`; full clear green, partial yellow;
  empty if not saved. Tooltip: per-difficulty boss list with killed/alive and
  time until reset.
- **Dungeons**: one column per season dungeon. Cell: ✓ if M0-saved, plus
  season best M+ level for that dungeon. Tooltip: lockout + reset time,
  season best.
- **World Bosses**: one column per current boss. Cell: ✓ / –. Tooltip: reset.
- **Weekly**: columns Vault Raid, Vault Dungeons, Vault World (each `x/3`
  with reward ilvl), Key, Rating, Delve currencies, 🎁 if unclaimed.
  Tooltip: per-slot threshold/progress/reward level.

### Detail panel (`UI/DetailPanel.lua`)
Docked to the right of the grid; closes with its own button or by clicking
the same row again.
1. **Header**: class/spec icon, name-realm, level, ilvl (overall/equipped),
   gold, last seen.
2. **Equipment**: slot icon, ilvl, track (e.g. "Hero 4/6"); red marker for
   missing enchant, socket marker for empty sockets. Hover → `GameTooltip:SetHyperlink(link)`.
3. **Consumables**: grouped by category, count per item, greyed at 0.
   "Edit" toggle shows checkboxes for every scan-set item; in edit mode a
   drop target accepts dragged items (`GetCursorInfo`) and an edit box
   accepts an item ID.
4. **This week**: the character's lockouts, vault, key, rating.
5. **Forget character** button (hidden for the current character).

### Minimap / LDB
- LDB launcher; LibDBIcon button (hideable).
- Left-click toggles window, right-click opens settings.
- Tooltip: count of characters with Vault ready, highest key in the warband.

### Settings (`UI/Settings.lua`)
Blizzard Settings vertical layout category "Lockout": minimum level shown,
show minimap icon, show other saved instances, window scale.

## 8. Testing

- **Automated (busted, Lua 5.1)** with `tests/wow_mock.lua` providing stubs
  for the APIs used:
  - `Reset`: expiry, extended lockouts, vault-ready derivation, boundary at
    exactly `resetAt`.
  - `Watchlist`: `IsShown` tri-state, `ScanSet` union, custom items.
  - `DB`: fresh init, migrations, forget character, current-char guard.
  - Collectors: normalization of mocked API return values into the record
    shape (instances with encounters, vault activities, M+ fields, equipment
    track parsing, missing enchant, bag counting limited to scan set).
  - Event bus: debounce coalescing, combat deferral.
- **Static**: `luacheck` with a WoW globals config.
- **Manual in-game checklist** (in `docs/testing.md`): two+ characters, raid
  kill appears with boss tooltip, reset rollover hides expired lockouts,
  vault-ready flag after reset, gear change updates ilvl/track/enchant
  warnings, watchlist toggle/add by drag and ID, forget character, Esc/resize/
  position persistence, minimap toggle, no Lua errors with `/console scriptErrors 1`.
