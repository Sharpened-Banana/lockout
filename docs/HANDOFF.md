# Handoff: Lockout addon

For a local Claude Code session (or a human) picking this up on a machine that can run World of Warcraft. Read this, then `README.md` and `docs/testing.md`.

## Where things stand

- The addon was built in a cloud session and merged to `main` (PR #1). It is feature-complete against the spec, but it **has never been run in the WoW client**.
- `lua5.1 tests/run.lua` passes 226 tests, and `luacheck .` reports 0 warnings. The tests run against a WoW API mock. They catch logic and Lua errors, not real-client behaviour.
- Target: Retail, Midnight patch 12.0.7 (`## Interface: 120007` in `Lockout.toc`).
- Design spec: `docs/superpowers/specs/2026-10-30-lockout-addon-design.md`. This is the source of truth for intent.
- Implementation plan: `docs/superpowers/plans/2026-10-30-lockout-addon.md`. Its Global Constraints still apply to new work.

## Warband scope (by design, not a bug)

- **Login required:** a character appears only after it has logged in once with the addon enabled. Addons can't read other characters from the server. Each character's data is as fresh as its last login, and the reset logic still expires lockouts while that character is offline.
- **One WoW game account:** `LockoutDB` is account-wide SavedVariables, stored per WoW game account (`WTF/Account/<name>/`). Characters on another WoW license under the same Battle.net account (WoW1, WoW2) can't be seen, even though the game counts them in the same warband. All realms on one license do show.

## What the local session should do first

1. **Install it.**
   - **Option A:** package it with the BigWigs packager (`release.sh`), which fetches the libraries listed in `.pkgmeta`.
   - **Option B:** copy the repo into `_retail_/Interface/AddOns/Lockout`. Then put LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 under `Libs/` at the paths in `embeds.xml`.
   - `Libs/` is gitignored. Without the libraries the addon still works, minus the minimap button.
   - If a `.pkgmeta` external URL fails to fetch (the wowace/curseforge SVN mirrors have moved before), update it.
2. **Run the in-game checklist** in `docs/testing.md` with `/console scriptErrors 1` on. Log in on two or three characters first. `/lockout debug` prints collector failures and missing APIs.
3. **Fill the empty data tables.** They were left empty because the source sites were unreachable when the addon was built, and the IDs were not guessed:
   - `Data/Consumables.lua` → `items = { [itemID] = "Flasks" | "Potions" | "Food" | "Runes" | "Oils" }`. Include every quality rank of the current-expansion flasks/phials, potions, food, augment rune and weapon oils/stones.
   - `Data/Content.lua` → `WORLD_BOSSES = { { key = "q<questID>", questID = n, name = "..." } }` and `DELVE_CURRENCIES = { { id = n, name = "..." } }`.
   - Source the IDs from Wowhead or wago.tools for 12.0.7, and put the item name in a trailing comment. Verify each one in game with `/dump C_Item.GetItemInfo(id)`, `/dump C_CurrencyInfo.GetCurrencyInfo(id)` or `/dump C_QuestLog.IsQuestFlaggedCompleted(id)`.
4. **Fix whatever the checklist turns up.** For each fix, write a failing test first where the behaviour can be mocked, then fix it, then run `lua5.1 tests/run.lua` and `luacheck .`.

## Highest-risk spots (unverified against the live client)

These were written from API knowledge and only exercised against stubs. Check these first:

- **Gear info:**
  - `Collectors/Equipment.lua` reads the upgrade track from `C_TooltipInfo.GetInventoryItem(...).lines[i].leftText`.
  - Empty sockets are counted as the `EMPTY_SOCKET_*` totals from `C_Item.GetItemStats`, minus the gems in the item link.
  - `Data/Content.lua` `ENCHANT_SLOTS` is a best guess at Midnight's enchantable slots. Off-hand counts only when it's a weapon.
- **Season discovery:** `Core/Season.lua` finds the current Encounter Journal tier by matching the expansion name. It skips the world-boss pseudo-instance by assuming it's named after the expansion. Historically that entry was named after a zone instead, so a stray, always-empty raid column may appear.
- **Settings page:** `UI/Settings.lua` uses `Settings.RegisterAddOnSetting` with the argument order from 11.x onward. The minimap checkbox is inverted through a metatable proxy; `Settings.RegisterProxySetting` would be cleaner if the proxy misbehaves.
- **Textures and atlases:**
  - `UI/Theme.lua` `Theme.Icon` uses `ReadyCheck-Ready`, `INV_Misc_Bag_10` and `UI-EmptySocket-Prismatic`.
  - The grid uses `auctionhouse-icon-favorite`, `UI-SortArrow`, `UI-OptionsButton`, the ChatFrame size grabber and class icon coordinates.
  - A missing texture fails silently, so check each one visually.
- **Detail panel:**
  - drag and drop onto the consumables drop zone (`GetCursorInfo` / `ClearCursor`)
  - the Forget popup passing the character's GUID to `OnAccept`
  - the edit-mode checkbox tick being visible
- **Extended lockouts:** an extended lockout that reports `reset = 0` is treated as expiring immediately. Check how extended lockouts actually display.
- **Midnight combat restrictions:** collection is deferred while `InCombatLockdown()`. Check for Lua errors during an active M+ key between pulls, when you are out of combat but in an instance with restrictions.

## Architecture in one screen

```
Collectors (logged-in character only)  →  LockoutDB.characters[GUID]  →  pure models  →  thin UI
```

- **`Core/Init.lua`:**
  - **Namespace and logging:** the namespace, plus `ns.Log` / `ns.LogOnce`.
  - **Callbacks:** `ns.On` / `ns.Fire`. The events are `DB_READY`, `DATA_UPDATED` and `WATCHLIST_CHANGED`.
  - **Collector bus:**
    - `ns.RegisterCollector{ name, events, requires, debounce, OnLogin, OnEvent, Collect(self, record, now) }`.
    - Each collector runs at most once per debounce window, and is deferred while in combat.
    - Each `Collect` runs in a `pcall`.
    - A collector whose `requires` API is missing disables itself and logs why.
  - **Slash commands:** `/lockout`, `/lo`, `ns.RegisterSlash`.
  - **ADDON_LOADED** is matched against the addon's own folder name.
- **`Core/DB.lua`:** SavedVariables setup, default settings, schema migrations, `Current()` and `Forget(guid)`.
- **`Core/Reset.lua`:** pure expiry logic (`IsExpired`, `Active`, `Vault`, `MythicPlus`) that always takes `now`.
- **`Core/Watchlist.lua`:**
  - **Rule:** a consumable is shown if the character has it switched on, or if it's a default and they haven't switched it off.
  - **`ScanSet`:** the defaults plus every item any character has a watchlist entry for, on or off. Switched-off items keep being counted.
- **`Core/Season.lua`:** current-season raids, dungeons and M+ maps from the Encounter Journal and `C_ChallengeMode`. It is cached per build number and rebuilt once per session.
- **`Collectors/*`:**
  - Character, Equipment, Instances, WorldBosses, Vault, MythicPlus, Delves, Bags.
  - Bags reads only the backpack, bags 1–4 and the reagent bag, never any bank.
  - Instance keys are `"<mapID>:<difficultyID>"`; Mythic 0 is difficulty 23.
- **`UI/Rows.lua` and `UI/Tabs/*`:** pure display models. Each tab provides `Columns(ctx)` and `Cell(char, col, ctx) → { text, color, tooltip }`. `"–"` means nothing to show.
- **`UI/Theme.lua`, `Grid.lua`, `MainFrame.lua`, `DetailPanel.lua`, `Minimap.lua`, `Settings.lua`:** rendering only.
  - **Load order:** the TOC order matters. `tests/toc_spec.lua` checks that it matches `tests/loader.lua`.

## Testing conventions

- Use `lua5.1 tests/run.lua`, the built-in busted-style runner. busted itself is not needed.
- **Loading code:** `tests/loader.lua` provides `loader.load(files, install)`. It resets the mock, runs `install()` so you can set API stubs **before** files load (collector `requires` are checked at load time), then loads the files.
- **Mock isolation:** `mock.reset()` removes any global created since its first call, so stubs don't leak between tests.
- **Mock contents:** `tests/wow_mock.lua` provides a manual clock (`mock.now`, `mock.advance`), event firing (`mock.fire`), combat state (`mock.inCombat`), and stub frames with real Show/Hide/IsShown/IsVisible, parents, points and text.
- **Key specs:**
  - `tests/e2e_spec.lua` loads the full TOC and runs a whole session for several saved-data shapes, including nil, empty, partial and malformed. Keep it green.
  - `tests/toc_spec.lua` keeps the TOC and the loader in sync. A new file must be added to both.

## Rules worth keeping

- Never invent game IDs. Source them from Wowhead or wago.tools and add the item name as a comment.
- Every file starts with `local _, ns = ...` (`Core/Init.lua` uses `local addonName, ns = ...`). No new globals beyond `LockoutDB`, the slash globals and `LockoutMainFrame`.
- Only collectors and the bus call `time()`; models take `now` as a parameter.
- Fonts can't draw ✓ 🎁 ◇ and similar symbols. Use `Theme.Icon` texture markup.
- Bags only. Never read the bank or the warband bank.

## Known minor issues (deferred, none blocking)

- `UI/DetailPanel.lua` is about 600 lines and `UI/Grid.lua` about 430. The natural split is to move each file's widget builders into a helper file.
- **Switched-off watchlist items:** a switched-off item stays in the bag scan forever, because there's no "remove item" action.
- **Detail panel item names:** uncached item names show as "Item N" until the next refresh. Nothing re-renders on `GET_ITEM_INFO_RECEIVED`.
- **Equipment rescans:** Equipment rescans on every `GET_ITEM_INFO_RECEIVED`, at most once per 0.5 s debounce window. Consider rescheduling only while a slot has `ilvl == nil`.
- **Character item level:** Character doesn't listen to `PLAYER_AVG_ITEM_LEVEL_UPDATE`.
- **Vault reward ilvl:** it stays missing if the example item link wasn't cached yet.
- **Raids cell color:** it uses the last difficulty in sort order, so an unknown difficulty sorts last and can set the color.
- **Weekly delves cell:** quantities are joined by position and skip currencies the character doesn't own.
- **Login flicker:** at login, Instances, WorldBosses and Vault may briefly write empty data before the server responds. Follow-up events correct it.
- **Panel position:** the detail panel isn't clamped to the screen when the window sits near the right edge.
- **Settings panel:**
  - `/lockout config` gives no feedback if the Settings API is missing.
  - The scale slider label may show raw floating-point values.
- **Upgrade-track pattern:** `Util.FormatToPattern` doesn't handle positional format specifiers (`%1$s`), which only matters for non-enUS locales.
- **Season data:** an empty season cache rebuilds on every `Get()` call.
- **Unconfirmed API detail:** `GetRunHistory(false, true)` is assumed to mean (include previous weeks = false, include incomplete runs = true). Over-time runs count toward weekly best, matching the Great Vault.

## Decisions made along the way (so you don't relitigate them)

- **Columns:** season raid and dungeon columns come from the Encounter Journal at runtime, not from a hard-coded list.
- **Weekly best:** weekly best counts all of this week's runs, including over-time keys, because those count for the Vault. The keystone itself is weekly data, so it's hidden after reset.
- **Delves:** delve currencies don't expire and show "updated <age>" instead.
- **Watchlist off:** switching a consumable off keeps its count; this was approved by the user.
- **Window position:** `settings.window` stores `{ point, relativePoint, x, y, w, h }`.
