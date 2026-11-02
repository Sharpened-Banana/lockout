# Holiday Bosses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While a holiday event is live, show its dungeon-finder holiday boss on the Legacy tab, with a check for each character that has had today's reward.

**Architecture:**
- A new Holidays collector reads the dungeon finder's random-dungeon list. It saves which holiday dungeons are live and which are done today into a new `holidays` record section, with a daily reset.
- The Legacy tab puts a "Holiday" heading and one row per live holiday boss above its Raids group. A holiday counts as live if any character recorded it today.
- The grid needs no changes.

**Tech Stack:** Lua 5.1 (WoW Retail 12.0.7 addon), with the repo's own busted-style runner and WoW API mock.

**Spec:** `docs/superpowers/specs/2026-11-01-holiday-bosses-design.md`. It builds on `2026-11-01-legacy-world-bosses-design.md`.

## Global Constraints

- Every file starts with `local _, ns = ...`. No new globals beyond `LockoutDB`, the slash globals and `LockoutMainFrame`.
- Only collectors and the bus call `time()`. Models take `now` from `ctx.now`.
- Never invent game IDs. This feature hard-codes none, because names and IDs come from the dungeon finder at runtime.
- Status markers are texture markup (`ns.Theme.Icon.check`), not font glyphs.
- A new file goes in both `Lockout.toc` and `tests/loader.lua` (`loader.ALL`), in the same order. `tests/toc_spec.lua` enforces this.
- Run tests with `luajit tests/run.lua` (there is no `lua5.1` on this machine). Lint with `luacheck .`. Both must be clean after every task.
- Commits use the repo-local identity that is already configured, stage files by path, and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work on branch `claude/holiday-bosses`. Do not push.

## Review Focus

1. The dungeon finder hasn't loaded at login (`GetNumRandomDungeons()` returns 0). The collector writes empty `active`/`done` tables, not nil, and the next `LFG_UPDATE_RANDOM_INFO` fills them. Pinned in Task 1.
2. `GetLFGDungeonInfo` returns nothing for a listed ID (still loading). That dungeon is skipped with no error, and the rest are still collected. Pinned in Task 1.
3. Two characters recorded the same holiday under different names, for example after a client language change. There is one row, with a stable name: sorted by name, the first wins. Pinned in Task 2.
4. A record whose `holidays` table lacks `active` or `done` (partial or old data) renders with no error and adds nothing. Pinned in Task 2.
5. A done entry with nil `resetAt` (the daily reset was unknown) still shows the check, with no tooltip. Pinned in Task 2.

---

### Task 1: Holidays collector and the `holidays` record section

**Files:**
- Create: `Collectors/Holidays.lua`
- Modify: `Core/DB.lua` (`SECTIONS`, and the nested-table guarantees in `DB.Current`)
- Modify: `Lockout.toc` and `tests/loader.lua` (add `Collectors/Holidays.lua` immediately after `Collectors/Bags.lua` in both)
- Test: `tests/weekly_collectors_spec.lua` (a new `describe("Holidays collector")`), `tests/db_spec.lua`, `tests/e2e_spec.lua`
- Docs: `docs/HANDOFF.md`, adding Holidays to the Collectors bullet list with one line on what it reads and its daily reset.

**Interfaces:**
- Produces: `record.holidays = { active = { [dungeonID] = { name = string, resetAt = number|nil } }, done = { [dungeonID] = { name, resetAt } } }`. It is rebuilt from scratch on every collect. `resetAt` is `Reset.Absolute(now, C_DateAndTime.GetSecondsUntilDailyReset())`.

- [ ] **Step 1: Write the failing tests**

In `tests/weekly_collectors_spec.lua`, add a "Holidays collector" block using `loadAddon({ "Collectors/Holidays.lua" }, stubs)`. Define these stubs:

```lua
local dungeons, infos, rewards, requested
local function stubs()
  dungeons, infos, rewards, requested = {}, {}, {}, 0
  GetNumRandomDungeons = function() return #dungeons end
  GetLFGRandomDungeonInfo = function(i) local d = dungeons[i]; return d.id, d.name end
  -- isHoliday is the 15th return
  GetLFGDungeonInfo = function(id)
    local h = infos[id]
    if not h then return nil end
    return h.name, 1, 0, 0, 0, 0, 0, 0, 0, 0, "", 0, 5, "", h.holiday
  end
  GetLFGDungeonRewards = function(id) return rewards[id] == true end
  RequestLFDPlayerLockInfo = function() requested = requested + 1 end
  C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
end
```

Write these tests:

- **"is registered with its events and requirements":** `def.events` equals `{ "LFG_UPDATE_RANDOM_INFO", "LFG_COMPLETION_REWARD" }`, and `def.disabled` is nil.
- **"requests dungeon info on login and after a reward":** calling `def.OnLogin()` gives `requested == 1`. `def.OnEvent("LFG_COMPLETION_REWARD")` gives 2. `def.OnEvent("LFG_UPDATE_RANDOM_INFO")` leaves it at 2.
- **"holiday dungeons are active, done when rewarded, others skipped":**
  - Setup: `dungeons = { { id = 285, name = "Headless Horseman" }, { id = 286, name = "Ahune" }, { id = 9, name = "Random Dungeon" } }`, with `infos[285] = { holiday = true }`, `infos[286] = { holiday = true }`, `infos[9] = { holiday = false }` and `rewards[285] = true`.
  - Expected:

    ```lua
    rec.holidays == { active = { [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 }, [286] = { name = "Ahune", resetAt = mock.now + 3600 } },
                      done = { [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 } } }
    ```
- **"falls back to the dungeon info name":** a listed `{ id = 287 }` with no name and `infos[287] = { name = "Coren Direbrew", holiday = true }` gives `active[287].name == "Coren Direbrew"`.
- **"empty list writes empty tables and drops stale entries":** with `rec.holidays = { active = { [1] = { name = "Old" } }, done = {} }` and no dungeons, collecting gives `rec.holidays == { active = {}, done = {} }`. This is Review Focus 1.
- **"a dungeon without info is skipped":** `dungeons = { { id = 400, name = "Loading" }, { id = 285, name = "Headless Horseman" } }`, with no `infos[400]` and `infos[285] = { holiday = true }`, gives an `active` with only 285 and no error. This is Review Focus 2.
- **"unknown daily reset leaves resetAt nil":** with `C_DateAndTime.GetSecondsUntilDailyReset = function() return nil end`, a holiday gives `active[id].resetAt == nil`.
- **"disables itself without the rewards API":** with an install that also sets `GetLFGDungeonRewards = nil`, `def.disabled` is true.

Elsewhere:

- **`tests/db_spec.lua`:** add `"holidays"` to the key list in "Current creates full record", and assert `rec.holidays.active` and `rec.holidays.done` are `{}`. In the partial-record test, assert that both nested tables exist.
- **`tests/e2e_spec.lua`:** in `install()`, add `GetNumRandomDungeons = function() return 0 end`, `GetLFGRandomDungeonInfo = function() end`, `GetLFGDungeonInfo = function() end`, `GetLFGDungeonRewards = function() return false end`, `RequestLFDPlayerLockInfo = function() end`, and `GetSecondsUntilDailyReset = function() return 3600 end` on the existing `C_DateAndTime` table. After the existing `current.legacyBosses` assertion, add `assert.same({ active = {}, done = {} }, current.holidays)`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua 2>&1 | grep -E "FAIL|passed"`
Expected: the loader errors on the missing `Collectors/Holidays.lua` for the new block (or `toc_spec` fails once the loader lists it), and the DB and e2e assertions fail.

- [ ] **Step 3: Implement**

- **`Collectors/Holidays.lua`:** use the `ns.RegisterCollector` definition from the spec's Collection section, with its events, `requires`, `OnLogin` and `OnEvent` as given there.
  - `Collect` walks `1 .. GetNumRandomDungeons()`. It skips a dungeon when `GetLFGDungeonInfo` returns nothing or its 15th return is falsy.
  - The name is the `GetLFGRandomDungeonInfo` name, falling back to the first return of `GetLFGDungeonInfo`.
  - `done` is set when the first return of `GetLFGDungeonRewards(id)` is truthy.
  - Assign the fresh `record.holidays`.
- **`Core/DB.lua`:** append `"holidays"` to `SECTIONS`. In `DB.Current`, add `rec.holidays.active = rec.holidays.active or {}` and the same for `done`, next to the existing nested guarantees.
- **TOC, loader and HANDOFF:** as listed under Files.

- [ ] **Step 4: Run the tests and lint to verify they pass**

Run: `luajit tests/run.lua 2>&1 | tail -1 && luacheck . | tail -1`
Expected: `N passed, 0 failed` and `0 warnings / 0 errors`. Specs that load the whole addon without the dungeon-finder stubs now see the Holidays collector disable itself and log a "disabled" line. If one of them asserts an empty log, add the same stubs to that spec's install instead of loosening the assertion.

- [ ] **Step 5: Commit**

```bash
git add Collectors/Holidays.lua Core/DB.lua Lockout.toc tests/loader.lua tests/weekly_collectors_spec.lua tests/db_spec.lua tests/e2e_spec.lua docs/HANDOFF.md
git commit -m "feat: collect live holiday bosses and today's rewards"
```

---

### Task 2: Holiday rows on the Legacy tab

**Files:**
- Modify: `UI/Tabs/Legacy.lua`
- Test: `tests/models_spec.lua` (the Legacy block), `tests/ui_smoke_spec.lua`
- Docs: `docs/testing.md` (the Legacy items), `README.md` (the Legacy sentence)

**Interfaces:**
- Consumes: `char.holidays.active` and `char.holidays.done` from Task 1. Either may be missing on old or partial records.
- Produces: `Legacy.Rows(ctx)` gains, before the Raids group, `{ heading = true, key = "h:holidays", label = "Holiday" }` followed by `{ kind = "holiday", key = "hd:" .. dungeonID, dungeonID = dungeonID, label = name }` rows. These appear only while a holiday is live in any record of `ctx.db.characters`. `Legacy.Cell` handles `kind == "holiday"`.

- [ ] **Step 1: Write the failing tests**

In the Legacy block of `tests/models_spec.lua`, `ctx.db.characters` defaults to `{}`, so the existing expectations stay as they are. Add:

```lua
it("no live holiday means no Holiday section", function()
  ctx.db.characters.g1 = { holidays = { active = { [285] = { name = "Headless Horseman", resetAt = NOW - 1 } }, done = {} } }
  for _, row in ipairs(ns.Tabs.Legacy.Rows(ctx)) do assert.is_not.equals("h:holidays", row.key) end
end)

it("live holidays head the tab, from any character, sorted by name", function()
  ctx.db.characters.hidden = { holidays = { active = {
    [286] = { name = "Lord Ahune", resetAt = NOW + 100 },
    [285] = { name = "Headless Horseman", resetAt = NOW + 100 } }, done = {} } }
  ctx.db.characters.other = { holidays = { active = { [285] = { name = "Kopflose Reiter", resetAt = NOW + 100 } } } } -- no done table
  ctx.db.characters.partial = { holidays = {} }                                                               -- no active table
  local rows = ns.Tabs.Legacy.Rows(ctx)
  assert.same({ heading = true, key = "h:holidays", label = "Holiday" }, rows[1])
  assert.same({ kind = "holiday", key = "hd:285", dungeonID = 285, label = "Headless Horseman" }, rows[2])
  assert.equals("Lord Ahune", rows[3].label)
  assert.equals("h:raids", rows[4].key)
end)

it("holiday cells: check when rewarded today, dash otherwise", function()
  local cols = ns.Tabs.Legacy.Columns(ctx)
  local row = { kind = "holiday", key = "hd:285", dungeonID = 285, label = "Headless Horseman" }
  ctx.characters[1].char.holidays = { done = { [285] = { name = "Headless Horseman", resetAt = NOW + 3600 } } }
  ctx.characters[2].char.holidays = { done = { [285] = { name = "Headless Horseman", resetAt = NOW - 1 } } }
  local cell = ns.Tabs.Legacy.Cell(row, cols[1], ctx)
  assert.equals(ns.Theme.Icon.check, cell.text)
  assert.same(ns.Rows.COLORS.green, cell.color)
  assert.equals("Headless Horseman", cell.title)
  assert.same({ { left = "Headless Horseman", right = "resets in 1h 0m" } }, cell.tooltip)
  assert.equals("–", ns.Tabs.Legacy.Cell(row, cols[2], ctx).text)  -- expired
  assert.equals("–", ns.Tabs.Legacy.Cell(row, cols[3], ctx).text)  -- no holidays section
  ctx.characters[1].char.holidays.done[285].resetAt = nil
  local unknown = ns.Tabs.Legacy.Cell(row, cols[1], ctx)
  assert.equals(ns.Theme.Icon.check, unknown.text)
  assert.is_nil(unknown.tooltip)
end)
```

The second test covers Review Focus 3 (the same ID with different names, "Headless Horseman" sorting before "Kopflose Reiter") and Review Focus 4 (missing `done` and `active` tables). The third covers Review Focus 5.

In `tests/ui_smoke_spec.lua`, add:

```lua
it("live holiday boss sits above the raids and opens its character", function()
  local grid = open()
  ns.Content.LEGACY_WORLD_BOSSES = {}
  local jaina = ns.db.characters["Player-2-0002"]
  jaina.holidays = { active = { [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 } },
                     done = { [285] = { name = "Headless Horseman", resetAt = mock.now + 3600 } } }
  ns.UI:SelectTab("Legacy")
  assert.same({ "Holiday", "Headless Horseman", "Raids", "Alpha Keep" }, labels(grid.rows))
  assert.equals(ns.Theme.Icon.check, grid.slots[2].cells[2].text:GetText()) -- Jaina
  assert.equals("–", grid.slots[2].cells[1].text:GetText())                 -- Thrall
  click(grid.slots[1].cells[2])
  assert.same({}, detail)
  click(grid.slots[2].cells[2])
  assert.same({ "Player-2-0002" }, detail)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua 2>&1 | grep -E "FAIL|passed"`
Expected: the three new Legacy model tests and the new smoke test fail. Nothing else fails.

- [ ] **Step 3: Implement in `UI/Tabs/Legacy.lua`**

- **Live holidays:** a local helper builds them from every record in `ctx.db.characters`, using `Reset.Active(char.holidays and char.holidays.active, ctx.now)`.
  - To get a deterministic name per dungeon ID, collect `(name, id)` pairs, sort them by name and then ID, and keep the first name seen for each ID.
  - Holiday rows are then ordered by that name.
  - `Rows` puts the heading and holiday rows first, ahead of the existing Raids and World bosses groups, which are unchanged.
- **`Cell`:** for `kind == "holiday"`, mirror `bossCell`, but with no drop line.
  - The kill is `Reset.Active(col.char and col.char.holidays and col.char.holidays.done, ctx.now)[row.dungeonID]`.
  - The tooltip line appears only when `resetAt` is set.
  - `title = row.label`.

- [ ] **Step 4: Run the tests and lint to verify they pass**

Run: `luajit tests/run.lua 2>&1 | tail -1 && luacheck . | tail -1`
Expected: `N passed, 0 failed` and `0 warnings / 0 errors`.

- [ ] **Step 5: Update the docs**

- **`docs/testing.md`:** add these Legacy items:
  - During a holiday event, its boss appears under a "Holiday" heading at the top of the Legacy tab.
  - After the day's first kill, that character gets a check without a `/reload`, and the check clears at the daily reset.
  - Outside events, there is no Holiday section.
  - `/dump select(15, GetLFGDungeonInfo(<id>))` returns true for the holiday dungeon. Take the ID from `/dump GetLFGRandomDungeonInfo(i)`. This confirms the holiday flag's return position on 12.0.7.
- **`README.md`:** extend the Legacy sentence with "and, while a holiday event runs, its dungeon-finder boss with today's loot status".

- [ ] **Step 6: Commit**

```bash
git add UI/Tabs/Legacy.lua tests/models_spec.lua tests/ui_smoke_spec.lua docs/testing.md README.md
git commit -m "feat: holiday boss rows on the Legacy tab"
```
