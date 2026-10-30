# Lockout Addon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Retail WoW addon that records each warband character's lockouts, weekly progress, gear and bag consumables, and shows them all in one tabbed grid window with a per-character detail panel.

**Architecture:** Collectors read game APIs for the logged-in character and write a GUID-keyed record into account-wide SavedVariables (`LockoutDB`). Pure-Lua "model" modules (reset expiry, watchlist, row building, tab cells) turn records into display data; thin UI files only render those models. Everything except rendering is unit-tested outside the game against a WoW API mock.

**Tech Stack:** Lua 5.1 (WoW dialect), WoW Retail API (Midnight 12.0.7), LibStub / CallbackHandler-1.0 / LibDataBroker-1.1 / LibDBIcon-1.0 (packager externals), in-repo test runner on `lua5.1`, `luacheck`.

**Spec:** `docs/superpowers/specs/2026-10-30-lockout-addon-design.md`

## Global Constraints

- Addon folder/name `Lockout`; SavedVariables `LockoutDB`; `## Interface: 120007`.
- Every file starts `local _, ns = ...` and adds to `ns`; no new globals except `LockoutDB`, `SLASH_LOCKOUT1 = "/lockout"`, `SLASH_LOCKOUT2 = "/lo"`, `SlashCmdList.LOCKOUT`, and `LockoutMainFrame` (needed for `UISpecialFrames`).
- Character key is `UnitGUID("player")`.
- Bags only: backpack, bags 1–4, reagent bag. Never bank or warband bank.
- No collection while `InCombatLockdown()`; run deferred work on `PLAYER_REGEN_ENABLED`.
- Every collector `Collect` runs inside `pcall`; failure logs once per collector per session, keeps old data.
- Pure modules take `now` as a parameter; only the bus and collectors call `time()`.
- **Never invent game IDs** (item, quest, currency). Data-file IDs must come from Wowhead/wago.tools for patch 12.0.7 with the name in a trailing comment. If a source can't be reached, ship the table empty with a `-- needs IDs` comment and report it to the user. Features must work with empty data tables.
- Tests: `lua5.1 tests/run.lua` (all specs) or `lua5.1 tests/run.lua tests/<file>_spec.lua`. Lint: `luacheck .` must report 0 warnings / 0 errors.
- Commit after each task, message prefix `feat:`/`test:`/`chore:`, ending with the session's attribution trailer.

### Deliberate refinements of the spec (decided here)
- Instance keys use the **map ID** returned by `GetSavedInstanceInfo` (14th return): `"<mapID>:<difficultyID>"`. Season columns join on the same map ID.
- Season raid/dungeon columns come from the Encounter Journal at runtime (`Core/Season.lua`), not a hard-coded list; only world-boss quests, delve currencies, enchantable slots and consumables are data files.
- M+ rating and per-dungeon season best come from `C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")` (one call) instead of `GetOverallDungeonScore` + `GetSeasonBestForMap`.
- The owned keystone is weekly data (it is replaced at reset). Delve currency quantities are **not** reset-expired; they show "updated <age>".
- Vault activities also store `rewardIlvl` (for the "x/3 · 678" cell).

## Review Focus

1. **Brand-new or partial record** (char logged in once, some collectors failed): every tab cell and the detail model must return "–"/empty, never error. → Task 11 `"renders empty record"` tests, Task 13 `"model of meta-only record"`.
2. **Item data not cached at login** (`GetDetailedItemLevelInfo`/tooltip return nil): store `ilvl = nil`, UI shows "?", no error; `GET_ITEM_INFO_RECEIVED` re-triggers Equipment. → Task 7 `"uncached item"` test.
3. **Filter text with Lua pattern characters** (`-`, `%`, `(`, `.`): name filter must use plain substring matching, case-insensitive. → Task 11 `"filter is plain text"` test.
4. **Same name on two realms**: rows stay distinct (GUID keys) and display `Name-Realm` when names collide. → Task 11 `"disambiguates duplicate names"` test.
5. **Vault claimed after reset**: once the live character is collected with no available rewards, the "ready" flag clears even though last week's progress existed. → Task 9 `"claimed vault clears ready"` test.

---

## File Structure

```
Lockout.toc  embeds.xml  .pkgmeta  .luacheckrc  .gitignore  README.md
Core/Init.lua        namespace, Log, callbacks (On/Fire), collector registry + event bus, slash cmds
Core/Util.lua        FormatToPattern, ParseItemLink, Age (relative time text)
Core/DB.lua          SavedVariables init/defaults/migrations, Current(), Forget()
Core/Reset.lua       pure expiry/view logic
Core/Watchlist.lua   pure watchlist logic
Core/Season.lua      current-season raid/dungeon/M+ columns from EJ + ChallengeMode, cached
Data/Consumables.lua curated default consumables by category
Data/Content.lua     world-boss quests, delve currencies, enchantable slots, equipment slots
Collectors/Character.lua Equipment.lua Instances.lua WorldBosses.lua Vault.lua MythicPlus.lua Delves.lua Bags.lua
UI/Rows.lua          pure: ordered row list from db + filters
UI/Tabs/Raids.lua Dungeons.lua WorldBosses.lua Weekly.lua   pure Columns()/Cell()
UI/Theme.lua  UI/Grid.lua  UI/MainFrame.lua  UI/DetailPanel.lua  UI/Minimap.lua  UI/Settings.lua
tests/run.lua  tests/wow_mock.lua  tests/loader.lua  tests/*_spec.lua
docs/testing.md
```

TOC load order (also `tests/loader.lua`'s `ALL` list): `embeds.xml`, Core/Init, Core/Util, Core/DB, Core/Reset, Core/Watchlist, Data/Consumables, Data/Content, Core/Season, Collectors/* (order above), UI/Theme, UI/Rows, UI/Tabs/*, UI/Grid, UI/DetailPanel, UI/MainFrame, UI/Minimap, UI/Settings.

---

### Task 1: Scaffold, test runner, WoW mock

**Files:**
- Create: `Lockout.toc`, `embeds.xml`, `.pkgmeta`, `.luacheckrc`, `.gitignore`, `README.md`
- Create: `tests/run.lua`, `tests/wow_mock.lua`, `tests/loader.lua`
- Test: `tests/harness_spec.lua`

**Interfaces:**
- Produces (test globals from `tests/run.lua`): `describe(name, fn)`, `it(name, fn)`, `before_each(fn)` (scoped to enclosing `describe`), `assert.equals(expected, actual)`, `assert.same(expected, actual)` (deep), `assert.is_true(v)`, `assert.is_false(v)`, `assert.is_nil(v)`, `assert.truthy(v)`, `assert.has_error(fn)`. Exit code 1 on any failure; prints `N passed, M failed` and each failure's `describe > it: message`.
- Produces (`tests/wow_mock.lua`, returned table `mock`): `mock.reset()` reinstalls all globals below and clears state; `mock.now` (default `1700000000`); `mock.advance(seconds)` moves `mock.now` and runs due `C_Timer.After` callbacks in order; `mock.inCombat` (bool); `mock.fire(event, ...)` dispatches to every mock frame registered for `event`; `mock.player = { guid="Player-1-0001", name="Thrall", realm="Draenor", classFile="SHAMAN", level=80 }`. Globals installed: `time`, `C_Timer.After`, `CreateFrame` (returns a universal stub frame: any unknown method is a no-op returning the frame; `RegisterEvent`, `UnregisterEvent`, `SetScript`, `GetScript` are real), `InCombatLockdown`, `UnitGUID`, `UnitName`, `UnitClass`, `UnitLevel`, `GetRealmName`, `UISpecialFrames = {}`, `Enum` (`WeeklyRewardChestThresholdType = {Activities=1, RankedPvP=2, Raid=3, World=6}`, `BagIndex = {Backpack=0, Bag_1=1, Bag_2=2, Bag_3=3, Bag_4=4, ReagentBag=5}`), `ITEM_UPGRADE_TOOLTIP_FORMAT_STRING = "Upgrade Level: %s %d/%d"`, `print` captured into `mock.printed`. Other API stubs are set per test.
- Produces (`tests/loader.lua`): `loader.load(files?) -> ns` — calls `mock.reset()`, then `loadfile(path)("Lockout", ns)` for each file (default `loader.ALL`, which excludes `embeds.xml`). `loader.CORE` = Init, Util, DB, Reset, Watchlist, Consumables, Content.

- [ ] **Step 1: Write scaffold files**
  - `Lockout.toc`: `## Interface: 120007`, `## Title: Lockout`, `## Notes: Warband lockouts, weekly progress, gear and consumables`, `## Author: lonezebra`, `## Version: @project-version@`, `## SavedVariables: LockoutDB`, `## IconTexture: Interface\Icons\INV_Misc_Key_14`, then the load order above.
  - `embeds.xml`: `<Ui>` including `Libs\LibStub\LibStub.lua`, `Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml`, `Libs\LibDataBroker-1.1\LibDataBroker-1.1.lua`, `Libs\LibDBIcon-1.0\lib.xml`.
  - `.pkgmeta`: `package-as: Lockout`; externals for those four paths (LibStub `https://repos.wowace.com/wow/libstub/trunk`, CallbackHandler `https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0`, LibDataBroker `https://github.com/tekkub/libdatabroker-1-1`, LibDBIcon `https://repos.curseforge.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0`); `ignore: [tests, docs, .luacheckrc]`.
  - `.gitignore`: `Libs/`, `.release/`.
  - `.luacheckrc`: `std = "lua51"`, `max_line_length = false`, `exclude_files = {"Libs/", ".release/"}`, `globals = {"LockoutDB","SLASH_LOCKOUT1","SLASH_LOCKOUT2","SlashCmdList","LockoutMainFrame","UISpecialFrames","StaticPopupDialogs"}`, `read_globals` listing every WoW API/global used in this plan (add as tasks use them), and `files["tests/"] = { std = "+busted", globals = {"assert","describe","it","before_each"}, allow_defined_top = true, ignore = {"111","112","113","121","122"} }` (tests and the mock legitimately set WoW globals).
  - `README.md`: one paragraph of what it does, install (packaged zip or copy folder + libs), `/lockout`, how to run tests and lint.

- [ ] **Step 2: Write harness self-test `tests/harness_spec.lua`**

```lua
describe("harness", function()
  local n
  before_each(function() n = 1 end)
  it("equals/same", function()
    assert.equals(1, n)
    assert.same({ a = { 1, 2 } }, { a = { 1, 2 } })
  end)
  it("has_error", function() assert.has_error(function() error("x") end) end)
end)
describe("mock", function()
  local mock = require("tests.wow_mock")
  it("timers run on advance in order", function()
    mock.reset(); local seen = {}
    C_Timer.After(2, function() seen[#seen + 1] = "b" end)
    C_Timer.After(1, function() seen[#seen + 1] = "a" end)
    mock.advance(1); assert.same({ "a" }, seen)
    mock.advance(1); assert.same({ "a", "b" }, seen)
  end)
  it("fire dispatches to registered frames", function()
    mock.reset(); local f = CreateFrame("Frame"); local got
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, e, a) got = e .. (a or "") end)
    mock.fire("PLAYER_LOGIN", "!"); assert.equals("PLAYER_LOGIN!", got)
    f:AnyUnknownMethod(); -- universal stub must not error
  end)
end)
```

- [ ] **Step 3: Run** `lua5.1 tests/run.lua tests/harness_spec.lua` — Expected: fails (`cannot open tests/run.lua`).
- [ ] **Step 4: Implement `tests/run.lua`, `tests/wow_mock.lua`, `tests/loader.lua`** per Interfaces. `run.lua` sets `package.path = "./?.lua;./?/init.lua;" .. package.path`, collects files from `arg` or `io.popen("ls tests/*_spec.lua")`, and runs each `it` in `pcall` after the chain of enclosing `before_each` hooks.
- [ ] **Step 5: Run** `lua5.1 tests/run.lua` and `luacheck .` — Expected: `4 passed, 0 failed`; luacheck `0 warnings / 0 errors`.
- [ ] **Step 6: Commit** `chore: scaffold addon, test runner and WoW mock`.

---

### Task 2: Core/Init — namespace, log, callbacks, collector bus

**Files:**
- Create: `Core/Init.lua`
- Test: `tests/bus_spec.lua`

**Interfaces:**
- Consumes: Task 1 mock.
- Produces:
  - `ns.Log(fmt, ...)` appends `string.format` result to `ns.log` (array); `ns.LogOnce(key, fmt, ...)` logs only the first time per `key` per session.
  - `ns.On(name, fn)`, `ns.Fire(name, ...)` — internal callbacks. Event name `"DATA_UPDATED"` is fired with the collector name after a successful collect.
  - `ns.RegisterCollector(def)` where `def = { name=string, events={string...}, requires={string...}, debounce=number|nil (default 0.5), OnLogin=function()|nil, OnEvent=function(event, ...)|nil, Collect=function(self, record, now) }`. `OnEvent` (if present) is called synchronously on each matching event before scheduling, even in combat. `requires` entries are dotted global paths (`"C_WeeklyRewards.GetActivities"`). If any is nil at registration, the collector is stored with `disabled = true` and `ns.Log("%s disabled: missing %s", name, path)`. Registered collectors live in `ns.collectors[name]`.
  - `ns.Schedule(name)` — debounce: if not pending, `C_Timer.After(def.debounce, run)`. `run`: if `InCombatLockdown()` → add to `ns.deferred` set; else `ok, err = pcall(def.Collect, def, ns.DB:Current(), time())`; on failure `ns.LogOnce(name, "%s failed: %s", name, err)`; on success `ns.Fire("DATA_UPDATED", name)`.
  - `ns.CollectNow(name)` — same as `run` without debounce (used by tests and UI refresh).
  - Event frame: on `ADDON_LOADED` with arg `"Lockout"` → `ns.DB:Init(LockoutDB)` then `ns.Fire("DB_READY")`; on `PLAYER_LOGIN` → for each enabled collector call `OnLogin` if present, then `ns.Schedule(name)`; on `PLAYER_REGEN_ENABLED` → schedule every deferred collector and clear the set; any other event → schedule every enabled collector listing that event.
  - `ns.RegisterSlash(sub, fn)` — `/lockout <sub> <rest>` dispatch; empty sub calls handler `""`. Unknown sub prints usage listing registered subs. Built-in: `"debug"` prints `ns.log` lines with `print("|cff33ff99Lockout|r " .. line)`.

- [ ] **Step 1: Write failing tests `tests/bus_spec.lua`** (load `{ "Core/Init.lua" }` and stub `ns.DB = { Current = function() return rec end }` with `rec = {}`):
  - `"debounces bursts"`: register `{name="T", events={"BAG_UPDATE_DELAYED"}, Collect=count++}`; fire event 3×; `mock.advance(0.5)`; `assert.equals(1, count)`.
  - `"defers in combat"`: `mock.inCombat = true`; fire; advance 0.5 → count 0; `mock.inCombat = false`; `mock.fire("PLAYER_REGEN_ENABLED")`; advance 0.5 → count 1.
  - `"pcall isolates failures and logs once"`: two collectors on same event, first errors; after two bursts second's count is 2 and `#ns.log == 1`, `ns.log[1]` contains `"A failed"`.
  - `"disables collector with missing API"`: `requires={"C_Nope.Fn"}` → `ns.collectors.X.disabled == true`, event fire never calls Collect, log contains `"missing C_Nope.Fn"`.
  - `"login calls OnLogin then collects"`: order recorded `{"onlogin","collect"}` after `mock.fire("PLAYER_LOGIN")` + advance.
  - `"fires DATA_UPDATED"`: `ns.On("DATA_UPDATED", fn)` receives `"T"`.
  - `"OnEvent runs before scheduling"`: collector with `OnEvent` recording calls; fire twice → 2 OnEvent calls, 1 Collect after advance.
  - `"slash dispatch"`: `ns.RegisterSlash("foo", fn)`; `SlashCmdList.LOCKOUT("foo bar")` calls `fn("bar")`.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/bus_spec.lua` — Expected: FAIL (`Core/Init.lua` missing).
- [ ] **Step 3: Implement `Core/Init.lua`** per Interfaces.
- [ ] **Step 4: Run** the spec + `luacheck .` — Expected: all pass, 0 warnings.
- [ ] **Step 5: Commit** `feat: core namespace, logging and collector event bus`.

---

### Task 3: Core/DB — saved variables, current record, forget

**Files:**
- Create: `Core/DB.lua`
- Test: `tests/db_spec.lua`

**Interfaces:**
- Produces:
  - `ns.DB.SCHEMA = 1`; `ns.DB.migrations = {}` (index `n` upgrades schema `n-1 → n`; empty for v1).
  - `ns.DB:Init(saved) -> db`: `saved` nil → fresh `{ schema = 1, settings = <defaults>, characters = {}, season = nil }`; existing → run migrations for `saved.schema < SCHEMA` in order, then fill missing settings keys from defaults (deep, without overwriting). Assigns global `LockoutDB = db` and `ns.db = db`.
  - Defaults: `settings = { minLevel = 10, minimap = { hide = false }, showLegacy = false, scale = 1.0, window = {}, favorites = {}, currentRealmOnly = false, sortKey = "ilvl", sortDesc = true }`.
  - `ns.DB:Current() -> record`: get-or-create `ns.db.characters[UnitGUID("player")]`, ensuring every section key exists: `meta, instances, worldBosses, vault, mythicPlus, delves, equipment, bags, watchlist` (tables; `bags = { counts = {} }`, `delves = { currencies = {} }`, `vault = { activities = {} }`).
  - `ns.DB:Forget(guid) -> boolean`: false if `guid == UnitGUID("player")` or unknown; else removes, removes from `settings.favorites`, fires `"DATA_UPDATED"`, returns true.

- [ ] **Step 1: Write failing tests** (load `loader.CORE`):
  - `"fresh init"`: `ns.DB:Init(nil)` → `LockoutDB.schema == 1`, `settings.minLevel == 10`, `settings.sortKey == "ilvl"`.
  - `"fills missing settings without overwriting"`: `Init({schema=1, settings={minLevel=1}, characters={}})` → minLevel 1, `minimap.hide == false`.
  - `"runs migrations in order"`: set `ns.DB.SCHEMA = 3`, migrations[2]/[3] append to a list; `Init({schema=1,...})` → list `{2,3}`, `schema == 3`.
  - `"Current creates full record"`: all nine section keys are tables; second call returns same table.
  - `"Forget refuses current character"` → false, record still there.
  - `"Forget removes other and favorite"`: characters["Player-1-0002"] + favorite → true, both gone.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/db_spec.lua` — Expected: FAIL.
- [ ] **Step 3: Implement `Core/DB.lua`.**
- [ ] **Step 4: Run** spec + lint — Expected: pass.
- [ ] **Step 5: Commit** `feat: saved variables, character records and forget`.

---

### Task 4: Core/Reset — pure expiry logic

**Files:**
- Create: `Core/Reset.lua`
- Test: `tests/reset_spec.lua`

**Interfaces:**
- Produces (all pure):
  - `ns.Reset.Absolute(now, seconds) -> number|nil` — nil if `seconds` nil, else `now + seconds`.
  - `ns.Reset.IsExpired(entry, now) -> boolean` — true if `entry == nil`; false if `entry.resetAt == nil`; else `now >= entry.resetAt`.
  - `ns.Reset.Active(map, now) -> table` — new table of entries in `map` (instances/worldBosses) not expired.
  - `ns.Reset.Vault(vault, now) -> { ready = bool, activities = list }` — not expired: `ready = vault.unclaimed == true`, activities as stored. Expired (or `resetAt` nil with activities present → treat as not expired): `ready = vault.unclaimed or any(progress >= threshold)`, activities copied with `progress = 0, rewardIlvl = nil`.
  - `ns.Reset.MythicPlus(mp, now) -> { key, weeklyBest, runs, rating, seasonBest }` — when expired, `key = nil, weeklyBest = 0, runs = {}`; rating and seasonBest always passed through (`rating` default 0, `seasonBest` default `{}`).

- [ ] **Step 1: Write failing tests:** `"Absolute"`; `"IsExpired boundary"` (`resetAt = 100`: now 99 → false, now 100 → true); `"nil entry expired, missing resetAt not"`; `"Active filters"`; `"vault not expired"` (unclaimed true → ready true); `"vault expired with completed slot is ready and zeroed"` (activity `{threshold=1, progress=2, rewardIlvl=678}` → ready, progress 0, rewardIlvl nil); `"vault expired no progress not ready"`; `"mythic plus expired keeps rating"` (`rating = 2500, seasonBest = {[501]=12}` survive, key nil, weeklyBest 0).
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/reset_spec.lua` — FAIL.
- [ ] **Step 3: Implement `Core/Reset.lua`.**
- [ ] **Step 4: Run** — pass + lint clean.
- [ ] **Step 5: Commit** `feat: reset expiry logic`.

---

### Task 5: Consumables data and Watchlist

**Files:**
- Create: `Data/Consumables.lua`, `Core/Watchlist.lua`
- Test: `tests/watchlist_spec.lua`

**Interfaces:**
- Produces:
  - `ns.Consumables.CATEGORIES = { "Flasks", "Potions", "Food", "Runes", "Oils" }` and `ns.Consumables.items = { [itemID] = category }` (all quality ranks of current-expansion items; IDs per Global Constraints).
  - `ns.Consumables.CategoryOf(itemID) -> string` — category or `"Other"`.
  - `ns.Watchlist.IsDefault(itemID) -> bool`
  - `ns.Watchlist.IsShown(char, itemID) -> bool` — tri-state per spec §6.
  - `ns.Watchlist.Set(char, itemID, on)` — `on` and default → `nil`; `on` and not default → `true`; not `on` → `false`.
  - `ns.Watchlist.ScanSet(db) -> { [itemID] = true }` — defaults ∪ every `true` in any character's watchlist.
  - `ns.Watchlist.Groups(char, db, editing) -> { { category = string, items = { { itemID, count, shown } ... } } ... }` — categories in `CATEGORIES` order then `"Other"`; empty groups omitted; items sorted by itemID. `editing == false` → only shown items; `true` → every scan-set item with its `shown` flag. `count = char.bags.counts[itemID] or 0`.

- [ ] **Step 1: Populate `Data/Consumables.lua`** from Wowhead/wago.tools for 12.0.7 (flasks/phials, combat + health potions, feast + stat food, augment rune, weapon oils/stones), every quality rank, `-- name (rank)` comments. Per Global Constraints, if sources unreachable ship `items = {}` with `-- needs IDs` and note it for the final report.
- [ ] **Step 2: Write failing tests** (tests set `ns.Consumables.items = { [1001]="Flasks", [1002]="Potions" }` so they don't depend on real IDs): `"default shown when nil"`; `"false hides default"`; `"true shows custom"`; `"Set back on default stores nil"`; `"ScanSet unions defaults and any char's true"` (char A `{[2001]=true}`, char B `{[2002]=false}` → {1001,1002,2001}); `"Groups hides off items unless editing"`; `"Groups puts custom under Other and orders categories"`; `"count defaults to 0"`.
- [ ] **Step 3: Run** `lua5.1 tests/run.lua tests/watchlist_spec.lua` — FAIL.
- [ ] **Step 4: Implement `Core/Watchlist.lua`** (+ `CategoryOf` in Consumables).
- [ ] **Step 5: Run** — pass + lint.
- [ ] **Step 6: Commit** `feat: consumable defaults and per-character watchlist`.

---

### Task 6: Content data and Season columns

**Files:**
- Create: `Data/Content.lua`, `Core/Season.lua`
- Test: `tests/season_spec.lua`

**Interfaces:**
- Produces:
  - `ns.Content.EQUIP_SLOTS = { 1,2,3,15,5,9,10,6,7,8,11,12,13,14,16,17 }` (display order: head, neck, shoulder, back, chest, wrist, hands, waist, legs, feet, rings, trinkets, weapons) and `ns.Content.SLOT_NAMES = { [1]="Head", ... }` using Blizzard globals `HEADSLOT` etc. with English fallback.
  - `ns.Content.ENCHANT_SLOTS = { [1]=true, [3]=true, [5]=true, [7]=true, [8]=true, [11]=true, [12]=true, [16]=true }` plus off-hand 17 handled in code when its equip loc is a weapon. Mark with `-- verify in game: Midnight enchantable slots` (checklist item in Task 14).
  - `ns.Content.WORLD_BOSSES = { { key = "q<questID>", questID = n, name = "..." } ... }` and `ns.Content.DELVE_CURRENCIES = { { id = n, name = "..." } ... }` — IDs per Global Constraints.
  - `ns.Season:Get() -> { raids = { {mapID, name, bosses} }, dungeons = { {mapID, name} }, mplus = { {challengeMapID, mapID, name} } }` — cached in `ns.db.season` keyed by `select(4, GetBuildInfo())`; rebuilt when the build differs or cache empty.
  - Build algorithm: find EJ tier whose `EJ_GetTierInfo(i)` name equals `_G["EXPANSION_NAME" .. LE_EXPANSION_LEVEL_CURRENT]`; remember `EJ_GetCurrentTier()`, `EJ_SelectTier(tier)`; raids = `EJ_GetInstanceByIndex(i, true)` until nil, skipping the one whose name equals the expansion name (world-boss pseudo-instance); `mapID = select(10, EJ_GetInstanceInfo(journalID))`; bosses counted via `EJ_GetEncounterInfoByIndex(j, journalID)` until nil; dungeons likewise with `false`; restore original tier. `mplus` from `C_ChallengeMode.GetMapTable()` + `C_ChallengeMode.GetMapUIInfo(id)` (name = 1st, mapID = 6th); dungeons list then gains any M+ map not already present (dedupe by mapID).

- [ ] **Step 1: Populate `WORLD_BOSSES` and `DELVE_CURRENCIES`** (Restored Coffer Key equivalent and coffer key shards for the current season) per Global Constraints.
- [ ] **Step 2: Write failing tests** with stubbed EJ (tiers `{"Classic","Midnight"}`, `EXPANSION_NAME11 = "Midnight"`, `LE_EXPANSION_LEVEL_CURRENT = 11`; raids `{"Raid A","Midnight"}`; dungeon `{"Dun A"}`; M+ maps `{501 → mapID 2001 "Dun A"}, {502 → 2002 "Old Dun"}`):
  - `"raids from current tier excluding world boss instance"` → one raid `{mapID=…, name="Raid A", bosses=…}`.
  - `"dungeons merge M+ maps without duplicates"` → names `{"Dun A","Old Dun"}`.
  - `"restores previously selected tier"` (EJ_SelectTier last called with original).
  - `"caches per build"`: second `Get()` with same build does not call EJ; changing `GetBuildInfo` build rebuilds.
- [ ] **Step 3: Run** `lua5.1 tests/run.lua tests/season_spec.lua` — FAIL.
- [ ] **Step 4: Implement `Data/Content.lua` and `Core/Season.lua`.**
- [ ] **Step 5: Run** — pass + lint.
- [ ] **Step 6: Commit** `feat: season content discovery and static data`.

---

### Task 7: Util, Character and Equipment collectors

**Files:**
- Create: `Core/Util.lua`, `Collectors/Character.lua`, `Collectors/Equipment.lua`
- Test: `tests/util_spec.lua`, `tests/character_equipment_spec.lua`

**Interfaces:**
- Produces:
  - `ns.Util.FormatToPattern(fmt) -> pattern` — escapes magic chars, `%s → (.-)`, `%d → (%d+)`, anchored `^…$`.
  - `ns.Util.ParseItemLink(link) -> { itemID, enchantID, gems = {g1..g4} }` (numbers; empty fields → 0).
  - `ns.Util.Age(seconds) -> string` — `"just now"` (<60), `"5m ago"`, `"3h ago"`, `"2d ago"`.
  - Collector `Character`: events `PLAYER_LEVEL_UP, PLAYER_SPECIALIZATION_CHANGED, PLAYER_MONEY, PLAYER_EQUIPMENT_CHANGED`; writes `record.meta = { name, realm, classFile, level, specID, ilvl, ilvlEquipped, gold, lastSeen = now }` (`ilvl, ilvlEquipped = GetAverageItemLevel()` rounded down; `specID = GetSpecializationInfo(GetSpecialization())` or nil).
  - Collector `Equipment`: events `PLAYER_EQUIPMENT_CHANGED, GET_ITEM_INFO_RECEIVED`; requires `C_TooltipInfo.GetInventoryItem, C_Item.GetDetailedItemLevelInfo`; for each `EQUIP_SLOTS` slot with a link writes `record.equipment[slot] = { link, itemID, ilvl, track, trackCur, trackMax, missingEnchant, emptySockets }`; empty slots removed. `track` from first tooltip line matching `FormatToPattern(ITEM_UPGRADE_TOOLTIP_FORMAT_STRING)`. `missingEnchant = enchantable and enchantID == 0` (17 enchantable only if `select(4, C_Item.GetItemInfoInstant(link))` is `INVTYPE_WEAPON` or `INVTYPE_WEAPONOFFHAND`). `emptySockets = max(0, sum of C_Item.GetItemStats(link) values whose key starts with "EMPTY_SOCKET_" - count of nonzero gems)`.

- [ ] **Step 1: Write failing tests**
  - util: `"pattern from upgrade format"` → `("Upgrade Level: Hero 4/6"):match(p)` returns `"Hero","4","6"`; `"escapes magic chars"` (`"a.b %d%%"` matches `"a.b 5%"` but not `"axb 5%"`); `"parses link"` (`"|cffa335ee|Hitem:212345:7000::213:0:0::...|h[X]|h|r"` → itemID 212345, enchant 7000, gems {0,213,0,0}... define the exact sample string in the test); `"Age buckets"`.
  - character: `"writes meta"` with stubs `GetAverageItemLevel → 662.7, 660.2`, `GetSpecialization → 2`, `GetSpecializationInfo(2) → 263`, `GetMoney → 123450000` → meta `{ilvl=662, ilvlEquipped=660, specID=263, gold=123450000, lastSeen=mock.now, name="Thrall", realm="Draenor", classFile="SHAMAN", level=80}`.
  - equipment: `"track, enchant, sockets"` (chest with enchant 0 → missingEnchant true; neck not enchantable → false; `GetItemStats` `{EMPTY_SOCKET_PRISMATIC=2}` and one gem → emptySockets 1; track `"Hero",4,6`); `"off-hand shield not enchantable"`; `"empty slot removed"`; `"uncached item"` (`GetDetailedItemLevelInfo → nil`, tooltip `nil`) → entry exists with `ilvl == nil, track == nil`, no error.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/util_spec.lua tests/character_equipment_spec.lua` — FAIL.
- [ ] **Step 3: Implement** the three files.
- [ ] **Step 4: Run** — pass + lint.
- [ ] **Step 5: Commit** `feat: character and equipment collectors`.

---

### Task 8: Instances and WorldBosses collectors

**Files:**
- Create: `Collectors/Instances.lua`, `Collectors/WorldBosses.lua`
- Test: `tests/instances_spec.lua`

**Interfaces:**
- Produces:
  - `Instances`: events `UPDATE_INSTANCE_INFO, BOSS_KILL, ENCOUNTER_END`; requires `GetNumSavedInstances, GetSavedInstanceInfo, GetSavedInstanceEncounterInfo, RequestRaidInfo`; `OnLogin = RequestRaidInfo`; `OnEvent` calls `RequestRaidInfo()` for `BOSS_KILL`/`ENCOUNTER_END` (the fresh data then arrives via `UPDATE_INSTANCE_INFO`). Rebuilds `record.instances` from scratch, only for `locked or extended` entries: key `mapID .. ":" .. difficultyID`, value `{ name, mapID, difficultyID, difficultyName, isRaid, resetAt = Reset.Absolute(now, reset), extended, killed = encounterProgress, total = numEncounters, encounters = { {name, killed} } }`.
  - `WorldBosses`: events `UPDATE_INSTANCE_INFO, QUEST_TURNED_IN`; requires `C_QuestLog.IsQuestFlaggedCompleted, C_DateAndTime.GetSecondsUntilWeeklyReset`; rebuilds `record.worldBosses`: from `GetSavedWorldBossInfo` (if present) key `"wb" .. worldBossID`, `resetAt = now + reset`; from `Content.WORLD_BOSSES` with completed quest → key `boss.key`, `resetAt = now + GetSecondsUntilWeeklyReset()`.

- [ ] **Step 1: Write failing tests:** `"stores locked raid with encounters"` (two saved instances, one `locked=false` → only one stored; key `"2657:16"`; encounters `{ {name="Boss1",killed=true},{name="Boss2",killed=false} }`; `resetAt = mock.now + 3600`); `"extended unlocked kept"`; `"rebuild drops stale"` (pre-existing key removed); `"boss kill requests raid info"` (fire `BOSS_KILL` → `RequestRaidInfo` called); `"quest world boss uses weekly reset"`; `"saved world boss api"`; `"works with empty WORLD_BOSSES"`.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/instances_spec.lua` — FAIL.
- [ ] **Step 3: Implement** both collectors.
- [ ] **Step 4: Run** full suite `lua5.1 tests/run.lua` + lint — pass.
- [ ] **Step 5: Commit** `feat: instance and world boss lockout collectors`.

---

### Task 9: Vault, MythicPlus and Delves collectors

**Files:**
- Create: `Collectors/Vault.lua`, `Collectors/MythicPlus.lua`, `Collectors/Delves.lua`
- Test: `tests/weekly_collectors_spec.lua`

**Interfaces:**
- Produces:
  - `Vault`: events `WEEKLY_REWARDS_UPDATE`; requires `C_WeeklyRewards.GetActivities, C_WeeklyRewards.HasAvailableRewards, C_DateAndTime.GetSecondsUntilWeeklyReset`; writes `record.vault = { resetAt = now + weekly, unclaimed = HasAvailableRewards(), activities = { {type, index, threshold, progress, level, rewardIlvl} } }` for types Raid, Activities, World only, sorted by type then index. `rewardIlvl` only when `progress >= threshold`: `C_Item.GetDetailedItemLevelInfo(C_WeeklyRewards.GetExampleRewardItemHyperlinks(id))`, nil-safe.
  - `MythicPlus`: events `CHALLENGE_MODE_COMPLETED, BAG_UPDATE_DELAYED, MYTHIC_PLUS_CURRENT_AFFIX_UPDATE`; requires `C_MythicPlus.GetOwnedKeystoneChallengeMapID, C_MythicPlus.GetOwnedKeystoneLevel, C_MythicPlus.GetRunHistory, C_PlayerInfo.GetPlayerMythicPlusRatingSummary`; writes `record.mythicPlus = { resetAt = now + weekly, key = mapID and {challengeMapID, level} or nil, runs = { {challengeMapID = mapChallengeModeID, level, completed} } (GetRunHistory(false, true)), weeklyBest = max run level or 0, rating = summary.currentSeasonScore or 0, seasonBest = { [challengeModeID] = bestRunLevel } }`.
  - `Delves`: events `CURRENCY_DISPLAY_UPDATE`; requires `C_CurrencyInfo.GetCurrencyInfo`; writes `record.delves = { updatedAt = now, currencies = { [id] = info.quantity } }` for `Content.DELVE_CURRENCIES` (skip nil info).

- [ ] **Step 1: Write failing tests:** `"vault keeps raid/activities/world only"` (a RankedPvP activity dropped); `"reward ilvl only for completed"`; `"claimed vault clears ready"` (record has stale expired vault with completed activity; collect with `HasAvailableRewards → false` and progress 0 → `ns.Reset.Vault(record.vault, mock.now).ready == false`); `"mythic plus key and weekly best"`; `"no key stores nil"`; `"rating summary nil-safe"` (summary nil → rating 0, seasonBest {}); `"delves currencies"`; `"delves empty data"`.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/weekly_collectors_spec.lua` — FAIL.
- [ ] **Step 3: Implement** the three collectors.
- [ ] **Step 4: Run** full suite + lint — pass.
- [ ] **Step 5: Commit** `feat: vault, mythic plus and delve collectors`.

---

### Task 10: Bags collector

**Files:**
- Create: `Collectors/Bags.lua`
- Test: `tests/bags_spec.lua`

**Interfaces:**
- Produces: `Bags`: events `BAG_UPDATE_DELAYED`; requires `C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo`; bags `Backpack, Bag_1..Bag_4, ReagentBag` from `Enum.BagIndex`; counts `stackCount` per `itemID` for items in `ns.Watchlist.ScanSet(ns.db)` only; writes `record.bags = { scannedAt = now, counts = { [itemID] = n } }` (zero-count scan-set items omitted). Also `ns.On("WATCHLIST_CHANGED", function() ns.Schedule("Bags") end)` — Task 13 fires it.

- [ ] **Step 1: Write failing tests:** `"counts scan-set items across bags and reagent bag"` (item in bag 0 ×3 and bag 5 ×2 → 5); `"ignores non-scan items"`; `"bank containers never read"` (stub records which bag IDs are queried; assert set equals `{0,1,2,3,4,5}`); `"rescans on WATCHLIST_CHANGED"`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement `Collectors/Bags.lua`.**
- [ ] **Step 4: Run** full suite + lint — pass.
- [ ] **Step 5: Commit** `feat: bag consumable collector`.

---

### Task 11: Row and tab models (pure)

**Files:**
- Create: `UI/Rows.lua`, `UI/Tabs/Raids.lua`, `UI/Tabs/Dungeons.lua`, `UI/Tabs/WorldBosses.lua`, `UI/Tabs/Weekly.lua`
- Test: `tests/models_spec.lua`

**Interfaces:**
- Consumes: `ns.Reset.*`, `ns.Season:Get()`, `ns.Content.*`, `ns.Util.Age`.
- Produces:
  - `ns.Rows.Build(db, opts) -> { { guid, char, label } ... }` where `opts = { minLevel, filter, realmOnly, realm, favorites, sortKey ("name"|"level"|"ilvl"), sortDesc }`. Filters: `meta.level >= minLevel` (missing level → 0, but the current character always included); `realmOnly` → `meta.realm == realm`; `filter` → case-insensitive `string.find(lower(name), lower(filter), 1, true)`. Order: favorites first, then sort key, then name, then guid. `label` = name, or `name .. "-" .. realm` when another *included* row shares the name.
  - Each tab module `ns.Tabs.<Name> = { title, order, Columns(ctx) -> { {key, label, width} }, Cell(char, col, ctx) -> { text, color = {r,g,b}|nil, tooltip = { {left, right?, color?} ... } } }`, `ctx = { db, season, settings, now }`. `ns.TabOrder = { "Raids", "Dungeons", "WorldBosses", "Weekly" }`.
  - Raids: columns = `season.raids` (key `mapID`), plus when `settings.showLegacy` every other `isRaid` mapID found in any char's active instances (label from stored name), ordered by name. Cell: for difficulties present in order LFR(17), N(14), H(15), M(16) join `"<L|N|H|M> k/n"` with two spaces; color green if the highest shown difficulty is full, yellow if partial; tooltip one header line per difficulty (`difficultyName`, `"resets in " .. duration`) then boss lines (`name`, `"Killed"`/`"Alive"`). Other difficulty IDs use the first letter of `difficultyName`.
  - Dungeons: columns = `season.dungeons`. Cell text: `"✓"` if active instance key `mapID:23` (Mythic 0) exists, plus `" +" .. best` where best = `seasonBest[challengeMapID]` for the M+ map with that mapID; `"–"` if neither.
  - WorldBosses: columns from `Content.WORLD_BOSSES` plus any `"wb…"` keys seen; cell `"✓"` (green) when active else `"–"`.
  - Weekly: columns `vaultRaid`, `vaultDungeons`, `vaultWorld` (text `"x/3"` + `" · " .. max rewardIlvl` when >0), `key` (`"+level name"` via season.mplus or `"–"`), `rating`, `delves` (joined `qty` per currency, tooltip names + `"updated " .. Age`), `ready` (`"🎁"` when `Reset.Vault(...).ready`).
  - Duration text helper `ns.Util.Duration(seconds)` → `"2d 4h"`, `"3h 5m"`, `"12m"` (add to `Core/Util.lua` with tests here).

- [ ] **Step 1: Write failing tests** using hand-built `db`/`season` fixtures:
  - Rows: `"min level hides but keeps current"`; `"realm only"`; `"favorites first then ilvl desc"`; `"filter is plain text"` (filter `"a-b"` matches name `"Xa-bY"`, filter `"%"` matches nothing and doesn't error, `"THR"` matches `"Thrall"`); `"disambiguates duplicate names"` (two "Thrall" on Draenor/Silvermoon → labels `"Thrall-Draenor"`, `"Thrall-Silvermoon"`).
  - Raids: `"cell badges and color"` (N 8/8 + H 4/8 → text `"N 8/8  H 4/8"`, yellow); `"expired lockout empty"`; `"legacy columns only when enabled"`; `"renders empty record"` (char `{meta={name="X"}}`; every tab's every column → text `"–"` or `""`, no error).
  - Dungeons: `"m0 and season best"` → `"✓ +12"`.
  - Weekly: `"vault cell"` (`2/3 · 678`); `"ready flag after reset"`; `"key name from season"`.
  - Util: `"Duration formats"`.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/models_spec.lua` — FAIL.
- [ ] **Step 3: Implement** Rows, the four tabs, `Util.Duration`.
- [ ] **Step 4: Run** full suite + lint — pass.
- [ ] **Step 5: Commit** `feat: row and tab display models`.

---

### Task 12: Theme, Grid and MainFrame rendering

**Files:**
- Create: `UI/Theme.lua`, `UI/Grid.lua`, `UI/MainFrame.lua`
- Test: `tests/ui_smoke_spec.lua`

**Interfaces:**
- Consumes: `ns.Rows.Build`, `ns.Tabs`, `ns.TabOrder`, `ns.Season:Get()`, `ns.On("DATA_UPDATED")`.
- Produces:
  - `ns.Theme = { bg = {0.07,0.07,0.09,0.95}, panel = {0.11,0.11,0.14,1}, border = {0.2,0.2,0.25,1}, accent = {0.2,0.6,1}, green = {0.3,0.85,0.4}, yellow = {1,0.82,0.2}, grey = {0.5,0.5,0.5}, ROW_H = 22, HEADER_H = 24, NAME_W = 190 }`, `ns.Theme.Backdrop(frame, color)` (uses `BackdropTemplate`, `Interface\Buttons\WHITE8x8`, 1px edge), `ns.Theme.ClassColor(classFile) -> r,g,b` (`C_ClassColor.GetClassColor` nil-safe → white).
  - `ns.Grid.New(parent) -> grid` with `grid:SetColumns(cols)`, `grid:SetRows(rows)`, `grid:SetCellProvider(fn(row, col) -> cell)`, `grid:SetOnRowClick(fn(row))`, `grid:SetOnHeaderClick(fn(key))`, `grid:Refresh()`. Frozen name column (star toggle + class-colored `label` + level + ilvl), horizontal `ScrollFrame` for data columns, vertical virtualization via a scroll bar offset recycling `ceil(height / ROW_H) + 1` row frames. Cell hover → `GameTooltip` lines from `cell.tooltip`. Header click on name/level/ilvl → `onHeaderClick("name"|"level"|"ilvl")`.
  - `ns.UI:Toggle()`, `ns.UI:Show()`, `ns.UI:Refresh()`, `ns.UI:SelectTab(name)`, `ns.UI.selectedGuid`. Main frame global name `LockoutMainFrame`, added to `UISpecialFrames`; movable, `SetResizable(true)`, `SetResizeBounds(640, 320)`, resize grip; on stop-moving/sizing save `settings.window = {point, x, y, w, h}`; `SetScale(settings.scale)`. Header: tab buttons per `TabOrder`, filter `EditBox` (`OnTextChanged` → Refresh), "Current realm" `CheckButton` (`settings.currentRealmOnly`), cog → `ns.Settings:Open()`. Refresh builds `ctx` with `now = time()` and `ns.Rows.Build(ns.db, opts from settings + filter + GetRealmName())`. Header click toggles `settings.sortKey/sortDesc`; star toggles `settings.favorites[guid]`; row click → `ns.Detail:Toggle(guid)` (Task 13). `DATA_UPDATED` → `Refresh()` when shown.
  - `ns.RegisterSlash("", function() ns.UI:Toggle() end)`.

- [ ] **Step 1: Write failing smoke test `tests/ui_smoke_spec.lua`**: load `loader.ALL` with extra stubs (`GameTooltip` universal stub, `C_ClassColor`, `GetBuildInfo`, EJ/ChallengeMode stubs returning nothing, `ns.Detail` stub if Task 13 not done); `ns.DB:Init(nil)`; seed two characters with Task 11 fixtures; `ns.UI:Show()`; for each tab `ns.UI:SelectTab(name)`; `ns.UI:Refresh()`; assert no error and `UISpecialFrames` contains `"LockoutMainFrame"`; `SlashCmdList.LOCKOUT("")` toggles shown state (mock frame tracks `Show/Hide/IsShown` — extend the universal stub so these three are real).
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/ui_smoke_spec.lua` — FAIL.
- [ ] **Step 3: Implement** Theme, Grid, MainFrame.
- [ ] **Step 4: Run** full suite + lint — pass.
- [ ] **Step 5: Commit** `feat: main window and character grid`.

---

### Task 13: Detail panel and watchlist editing

**Files:**
- Create: `UI/DetailPanel.lua`
- Test: `tests/detail_spec.lua`

**Interfaces:**
- Consumes: `ns.Watchlist.Groups/Set/IsDefault`, `ns.Reset.*`, `ns.Content.EQUIP_SLOTS/SLOT_NAMES`, `ns.Util.Age`, `ns.DB:Forget`.
- Produces:
  - `ns.Detail.Model(guid, db, now, currentGuid) -> { header = { label, classFile, specID, level, ilvl, ilvlEquipped, gold, lastSeen = Age(now - meta.lastSeen) | "never" }, equipment = { {slot, slotName, link, ilvl, track = "Hero 4/6"|nil, missingEnchant, emptySockets} ... (EQUIP_SLOTS order, missing slots as {slot, slotName}) }, consumables = Watchlist.Groups(char, db, editing), week = { raids = n active raid lockouts, dungeons = n active M0, vault = Reset.Vault(...), mplus = Reset.MythicPlus(...) }, canForget = guid ~= currentGuid }`.
  - `ns.Detail:Toggle(guid)` — opens docked to the right of `LockoutMainFrame` (width 320, same height), same guid again closes; `ns.Detail:Refresh()` on `DATA_UPDATED`.
  - Rendering: header (class icon via `CLASS_ICON_TCOORDS` or spec icon `GetSpecializationInfoByID`), gold via `GetMoneyString`; equipment rows (icon `C_Item.GetItemIconByID`, ilvl or `"?"`, track, red `"No enchant"`, `"◇×n"` sockets; hover `GameTooltip:SetHyperlink(link)`); consumables groups with counts (count 0 greyed); "Edit" button toggles `editing`: rows become `CheckButton`s calling `Watchlist.Set` then `ns.Fire("WATCHLIST_CHANGED")`; in edit mode a drop zone (`OnReceiveDrag`/`OnMouseUp` reads `GetCursorInfo()` → `"item", itemID` → `Set(char, itemID, true)`, `ClearCursor()`) and an item-ID `EditBox` (numeric, Enter → same). "Forget character" button when `canForget` → `StaticPopupDialogs.LOCKOUT_FORGET` (`text = "Forget %s? Their saved data will be removed."`, Accept → `ns.DB:Forget(guid)`, close panel).

- [ ] **Step 1: Write failing tests:** `"model of full record"` (track string `"Hero 4/6"`, lastSeen `"2h ago"`, week counts); `"model of meta-only record"` (all 16 equipment rows with nil link, consumables `{}`, `week.vault.ready == false`, no error); `"cannot forget current"`; `"edit add by id fires WATCHLIST_CHANGED"` (call the exported helper `ns.Detail.AddItem(guid, itemID)` → watchlist true + event fired); smoke: `ns.Detail:Toggle(guid)` twice with universal stubs, no error.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/detail_spec.lua` — FAIL.
- [ ] **Step 3: Implement `UI/DetailPanel.lua`** (export `ns.Detail.AddItem(guid, itemID)` used by drop zone and edit box).
- [ ] **Step 4: Run** full suite + lint — pass.
- [ ] **Step 5: Commit** `feat: character detail panel with watchlist editing`.

---

### Task 14: Minimap, Settings, docs and release check

**Files:**
- Create: `UI/Minimap.lua`, `UI/Settings.lua`, `docs/testing.md`
- Modify: `README.md`, `.luacheckrc` (final read_globals)
- Test: extend `tests/ui_smoke_spec.lua`

**Interfaces:**
- Produces:
  - Minimap: if `LibStub` and `LibStub("LibDataBroker-1.1", true)` exist → `NewDataObject("Lockout", { type = "launcher", icon = "Interface\\Icons\\INV_Misc_Key_14", OnClick(_, button) → "LeftButton" toggles UI, "RightButton" opens settings; OnTooltipShow(tt) → "Lockout", "Vault ready: N characters", "Highest key: +L name (Char)" })`; LibDBIcon `Register("Lockout", obj, ns.db.settings.minimap)` on `DB_READY`. No libs → `ns.Log("minimap libs missing")`, no error. `ns.Minimap.Summary(db, now) -> { ready = n, bestKey = {level, challengeMapID, label} | nil }` pure.
  - Settings: `Settings.RegisterVerticalLayoutCategory("Lockout")` with `Settings.RegisterAddOnSetting` + `CreateSlider`/`CreateCheckbox` for minLevel (1–90 step 1), minimap show (inverts `minimap.hide`, calls `LibDBIcon:Show/Hide`), showLegacy, scale (0.7–1.5 step 0.05); changes call `ns.UI:Refresh()`. `ns.Settings:Open()` → `Settings.OpenToCategory(category:GetID())`. Guard if `Settings` global missing (log). `ns.RegisterSlash("config", function() ns.Settings:Open() end)`.
  - `docs/testing.md`: the spec §8 manual checklist as checkboxes, plus: verify Midnight `ENCHANT_SLOTS`, verify every data-file ID resolves to the commented name (`/dump C_Item.GetItemInfo(id)`, `/dump C_CurrencyInfo.GetCurrencyInfo(id)`), test with libs absent, `/lockout debug` shows no failures.

- [ ] **Step 1: Write failing tests:** `"summary counts ready and best key"` (two chars, one ready, keys +10/+12 → bestKey level 12 with that char's label); smoke: load with no `LibStub` and no `Settings` → no error and log contains `"minimap libs missing"`; with stub `Settings` (universal) → `SlashCmdList.LOCKOUT("config")` calls `Settings.OpenToCategory`.
- [ ] **Step 2: Run** `lua5.1 tests/run.lua tests/ui_smoke_spec.lua` — FAIL.
- [ ] **Step 3: Implement** Minimap and Settings; write `docs/testing.md`; finish README (install, commands `/lockout`, `/lockout config`, `/lockout debug`, dev: tests + lint + packaging via BigWigs packager).
- [ ] **Step 4: Verify** `lua5.1 tests/run.lua` (all pass, report counts) and `luacheck .` (0/0). Confirm TOC file list matches files on disk: `grep -v '^#' Lockout.toc | sed '/^$/d' | while read f; do [ -f "${f//\\//}" ] || echo MISSING $f; done` → no output.
- [ ] **Step 5: Commit** `feat: minimap button, settings and testing docs`.
- [ ] **Step 6: Report** to the user: test/lint results, any data tables shipped empty (`-- needs IDs`), and that the in-game checklist in `docs/testing.md` is the remaining verification.
