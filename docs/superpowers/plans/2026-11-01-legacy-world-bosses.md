# Legacy World Bosses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a fixed farm list of old world bosses as rows on the Legacy tab, with a check for each character that has looted that boss this week.

**Architecture:**
- The world-boss collector also checks each listed boss's hidden weekly quest. It stores the kills in a new `legacyBosses` record section.
- The Legacy tab adds "Raids" and "World bosses" heading rows, plus one always-present row per listed boss.
- The grid renders heading rows as plain accent-colored labels that ignore clicks.

**Tech Stack:** Lua 5.1 (WoW Retail 12.0.7 addon), with the repo's own busted-style runner and WoW API mock.

**Spec:** `docs/superpowers/specs/2026-11-01-legacy-world-bosses-design.md`. It extends `docs/superpowers/specs/2026-10-30-lockout-addon-design.md`.

## Global Constraints

- Every file starts with `local _, ns = ...`. No new globals beyond `LockoutDB`, the slash globals and `LockoutMainFrame`.
- Only collectors and the bus call `time()`. Models take `now` from `ctx.now`.
- Never invent game IDs. Source them from Wowhead or wago.tools for patch 12.0.7, and put the name in a trailing comment.
- Status markers are texture markup (`ns.Theme.Icon.check`), not font glyphs.
- Run tests with `luajit tests/run.lua` (there is no `lua5.1` on this machine). Lint with `luacheck .`. Both must be clean after every task.
- Commits use the repo-local identity that is already configured, and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Work on branch `claude/legacy-tab`.

## Review Focus

1. A character whose saved record predates this change has no `legacyBosses`. Its boss cells read "–", with no error. Pinned in Task 2.
2. A farm-list entry with no `drop` gets a tooltip with only the reset line on a kill, and no tooltip otherwise. Nothing concatenates nil. Pinned in Task 2.
3. A heading row's cells sit under character columns, but clicking one must not open that character's detail panel. Pinned in Task 3.
4. A malformed farm-list entry (a `key` that isn't `"q" .. questID`, a duplicate key, or a missing name) is caught by a data test, not shown as a broken row in game. Pinned in Task 4.
5. A name filter matching nobody leaves the boss rows listed with no columns, and nothing errors. Pinned in Task 3.

---

### Task 1: Collect legacy boss kills into `legacyBosses`

**Files:**
- Modify: `Data/Content.lua` (add the empty list after `WORLD_BOSSES`)
- Modify: `Collectors/WorldBosses.lua`
- Modify: `Core/DB.lua` (the `SECTIONS` list in `DB.Current`)
- Test: `tests/instances_spec.lua` ("WorldBosses collector" block), `tests/db_spec.lua`, `tests/e2e_spec.lua`

**Interfaces:**
- Produces:
  - `ns.Content.LEGACY_WORLD_BOSSES`: an array of `{ key = "q<questID>", questID = number, name = string, drop = string|nil }`, in display order. It starts empty here, and Task 4 fills it.
  - `record.legacyBosses[key] = { name = string, resetAt = number }` for each listed boss whose quest is complete. The collector rebuilds it from scratch on each run.

- [ ] **Step 1: Write the failing tests**

In the WorldBosses collector block of `tests/instances_spec.lua`:

```lua
it("legacy bosses go to legacyBosses with the weekly reset", function()
  local ns, def, rec = setup()
  ns.Content.LEGACY_WORLD_BOSSES = {
    { key = "q333", questID = 333, name = "Old Boss", drop = "Mount" },
    { key = "q444", questID = 444, name = "Other Old Boss" },
  }
  completed[333] = true
  def:Collect(rec, mock.now)
  assert.same({ q333 = { name = "Old Boss", resetAt = mock.now + 7200 } }, rec.legacyBosses)
  assert.same({}, rec.worldBosses)
end)

it("legacy bosses rebuild from scratch", function()
  local ns, def, rec = setup()
  ns.Content.LEGACY_WORLD_BOSSES = { { key = "q333", questID = 333, name = "Old Boss" } }
  rec.legacyBosses.stale = { name = "Stale", resetAt = 1 }
  def:Collect(rec, mock.now)
  assert.same({}, rec.legacyBosses)
end)
```

- `tests/db_spec.lua`: add `"legacyBosses"` to the key list in "Current creates full record". In "Current fills sections missing from a partial record", assert `type(rec.legacyBosses) == "table"`.
- `tests/e2e_spec.lua`: after `assert.truthy(current.instances["2100:15"])`, add `assert.same({}, current.legacyBosses)`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua 2>&1 | grep -E "FAIL|passed"`
Expected: FAIL on both new collector tests (`rec.legacyBosses` is nil or `LEGACY_WORLD_BOSSES` is unused), the two DB assertions and the e2e assertion.

- [ ] **Step 3: Implement**

- `Data/Content.lua`: add `Content.LEGACY_WORLD_BOSSES = {}`, with a comment giving its shape and noting that it needs IDs for patch 12.0.7, matching the `WORLD_BOSSES` block above it.
- `Core/DB.lua`: append `"legacyBosses"` to `SECTIONS`.
- `Collectors/WorldBosses.lua`: in `Collect`, build a second table with the same loop as the `WORLD_BOSSES` quest loop, reusing the `weekly` value. Assign it to `record.legacyBosses`. Leave events, `requires` and debounce unchanged.

- [ ] **Step 4: Run the tests and lint to verify they pass**

Run: `luajit tests/run.lua 2>&1 | tail -1 && luacheck . | tail -1`
Expected: `N passed, 0 failed` and `0 warnings / 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add Data/Content.lua Collectors/WorldBosses.lua Core/DB.lua tests/instances_spec.lua tests/db_spec.lua tests/e2e_spec.lua
git commit -m "feat: collect legacy world boss kills into legacyBosses"
```

---

### Task 2: Legacy tab rows and cells for headings and bosses

**Files:**
- Modify: `UI/Tabs/Legacy.lua`
- Test: `tests/models_spec.lua` ("Legacy" block)

**Interfaces:**
- Consumes: `ns.Content.LEGACY_WORLD_BOSSES` and `char.legacyBosses` from Task 1.
- Produces: `Legacy.Rows(ctx)` returns, in order:
  - `{ heading = true, key = "h:raids", label = "Raids" }`, only when there's at least one raid row.
  - Raid rows `{ kind = "raid", key = mapID, label = name }`, sorted as today.
  - `{ heading = true, key = "h:bosses", label = "World bosses" }`, only when the farm list is non-empty.
  - Boss rows `{ kind = "boss", key = boss.key, label = boss.name, boss = boss }`, in data order. They always appear, whoever is shown.

  `Legacy.Cell(row, col, ctx)` returns `{ text = "" }` for a heading row.

- [ ] **Step 1: Update the existing Legacy model tests and write the failing ones**

Update the existing expectations to the new row shape. For example, "rows are the active non-season raids…" now expects:

```lua
{ { heading = true, key = "h:raids", label = "Raids" },
  { kind = "raid", key = 400, label = "Old Sanctum" }, { kind = "raid", key = 300, label = "Zeta Ruins" } }
```

In "cells read like the raid tab…", the raid row literal gains `kind = "raid"`. In "empty without characters or a season", `assert.same({}, …Rows(ctx))` still holds, because the farm list is empty there.

Add, with `ns.Content.LEGACY_WORLD_BOSSES = { { key = "q333", questID = 333, name = "Galleon Test", drop = "Son of Galleon" }, { key = "q444", questID = 444, name = "No Drop Boss" } }` and Thrall's record (`ctx.characters[1].char`) given `legacyBosses = { q333 = { name = "Galleon Test", resetAt = NOW + 3600 }, q444 = { name = "No Drop Boss", resetAt = NOW - 1 } }`:

```lua
it("boss rows always follow a World bosses heading, in data order", function()
  local rows = ns.Tabs.Legacy.Rows(ctx)
  local n = #rows
  assert.same({ heading = true, key = "h:bosses", label = "World bosses" }, rows[n - 2])
  assert.equals("q333", rows[n - 1].key)
  assert.equals("boss", rows[n - 1].kind)
  assert.equals("No Drop Boss", rows[n].label)
  ctx.characters = {}
  assert.same({ "h:bosses", "q333", "q444" }, (function(r) local k = {} for i, x in ipairs(r) do k[i] = x.key end return k end)(ns.Tabs.Legacy.Rows(ctx)))
end)

it("boss cells: check with drop and reset when killed, dash otherwise", function()
  local cols = ns.Tabs.Legacy.Columns(ctx)
  local rows = ns.Tabs.Legacy.Rows(ctx)
  local galleon, nodrop = rows[#rows - 1], rows[#rows]
  local cell = ns.Tabs.Legacy.Cell(galleon, cols[1], ctx)
  assert.equals(ns.Theme.Icon.check, cell.text)
  assert.same(ns.Rows.COLORS.green, cell.color)
  assert.equals("Galleon Test", cell.title)
  assert.same({ { left = "Son of Galleon" }, { left = "Galleon Test", right = "resets in 1h 0m" } }, cell.tooltip)
  local open = ns.Tabs.Legacy.Cell(galleon, cols[2], ctx)       -- Jaina: no kill
  assert.equals("–", open.text)
  assert.same({ { left = "Son of Galleon" } }, open.tooltip)
  local expired = ns.Tabs.Legacy.Cell(nodrop, cols[1], ctx)     -- expired kill, no drop
  assert.equals("–", expired.text)
  assert.is_nil(expired.tooltip)
  assert.equals("–", ns.Tabs.Legacy.Cell(galleon, cols[3], ctx).text) -- Fresh: no legacyBosses section
end)

it("heading cells are blank", function()
  local cols = ns.Tabs.Legacy.Columns(ctx)
  assert.same({ text = "" }, ns.Tabs.Legacy.Cell({ heading = true, key = "h:bosses", label = "World bosses" }, cols[1], ctx))
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua 2>&1 | grep -E "FAIL Tab models > Legacy|passed"`
Expected: FAIL on the updated and the new Legacy tests.

- [ ] **Step 3: Implement in `UI/Tabs/Legacy.lua`**

- `Legacy.Rows`: build the raid rows as today, adding `kind = "raid"`, then assemble the heading and boss groups as in the Interfaces block.
- `Legacy.Cell`: dispatch on the row.
  - **Heading:** `{ text = "" }`.
  - **Raid:** the existing `Raids.LockoutCell` path, with `title`.
  - **Boss:** look up `Reset.Active(col.char and col.char.legacyBosses, ctx.now)[row.key]`.
    - The tooltip is `{ left = boss.drop }` when `drop` is set, followed on a kill by `{ left = boss.name, right = "resets in " .. Util.Duration(resetAt - ctx.now) }`.
    - When the tooltip would be empty, use `nil`.
    - Text is `Icon.check` with green on a kill, `Rows.EMPTY` otherwise. `title = boss.name`.

- [ ] **Step 4: Run the tests and lint to verify they pass**

Run: `luajit tests/run.lua 2>&1 | tail -1 && luacheck . | tail -1`
Expected: models pass. UI smoke tests that assert the Legacy rows (`{ "Alpha Keep" }`) fail until Task 3, and that's expected. No other failures.

- [ ] **Step 5: Commit**

```bash
git add UI/Tabs/Legacy.lua tests/models_spec.lua
git commit -m "feat: heading and world boss rows on the Legacy tab"
```

---

### Task 3: Grid renders heading rows and ignores their clicks

**Files:**
- Modify: `UI/Grid.lua` (`fillSlot`, `setHover`)
- Modify: `UI/MainFrame.lua` (`onRowClick`)
- Test: `tests/ui_smoke_spec.lua` (the "legacy tab lists raids…" test and a new test)

**Interfaces:**
- Consumes: `row.heading` and `row.kind` from Task 2.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Update the existing smoke test and write the failing one**

In "legacy tab lists raids down the side and characters across":
- Set `ns.Content.LEGACY_WORLD_BOSSES = {}` at the top, so Task 4's real data can't change it.
- Expect `{ "Raids", "Alpha Keep" }`, and the raid row at `grid.slots[2]`, not `slots[1]`.
- Shift each `slot`-based assertion to `grid.slots[2]`.
- With the "jai" filter, expect `0` rows: no raids, and an empty farm list.

New test:

```lua
it("legacy heading rows are accent labels that open nothing", function()
  local grid = open()
  ns.Content.LEGACY_WORLD_BOSSES = { { key = "q333", questID = 333, name = "Old Boss", drop = "Mount" } }
  local jaina = ns.db.characters["Player-2-0002"]
  jaina.legacyBosses = { q333 = { name = "Old Boss", resetAt = mock.now + 3600 } }
  -- a second old raid puts the World bosses heading on an even (striped) row
  jaina.instances = { ["300:14"] = { name = "Beta Ruins", mapID = 300, difficultyID = 14, difficultyName = "Normal",
    isRaid = true, resetAt = mock.now + 3600, killed = 1, total = 5, encounters = {} } }
  ns.UI:SelectTab("Legacy")
  assert.same({ "Raids", "Alpha Keep", "Beta Ruins", "World bosses", "Old Boss" }, labels(grid.rows))

  local heading = grid.slots[4]
  assert.same(ns.Theme.accent, { heading.name:GetTextColor() })
  assert.is_false(heading.left.deco.zebra:IsShown())
  assert.equals("", heading.cells[1].text:GetText())
  heading.left:GetScript("OnEnter")(heading.left)
  assert.is_false(heading.left.deco.hover:IsShown())
  click(heading.left)
  click(heading.cells[2])
  assert.same({}, detail)

  local boss = grid.slots[5]
  assert.equals(ns.Theme.Icon.check, boss.cells[2].text:GetText())   -- Jaina killed it
  assert.equals("–", boss.cells[1].text:GetText())
  click(boss.cells[2])
  assert.same({ "Player-2-0002" }, detail)

  -- a filter that matches nobody keeps the boss rows, with no columns
  ns.UI.filter:SetText("zzz")
  ns.UI.filter:GetScript("OnTextChanged")(ns.UI.filter, true)
  assert.same({ "World bosses", "Old Boss" }, labels(grid.rows))
  assert.equals(0, #grid.columns)
end)
```

`ns.Theme.accent` has three components, so `GetTextColor` returns three values to compare.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua 2>&1 | grep -E "FAIL UI smoke|passed"`
Expected: FAIL on the heading color, zebra, hover and the click on the heading cell (which currently opens Jaina).

- [ ] **Step 3: Implement**

- **`UI/MainFrame.lua` `onRowClick`:** return first when `row.heading`.
- **`UI/Grid.lua` `fillSlot`:** for `row.heading`, hide the zebra on both parts, ignore selection, and set the name color to `Theme.accent`. Cells already come back blank from the tab.
- **`UI/Grid.lua` `setHover`:** do nothing when `slot.row and slot.row.heading`. This covers the name frame, the star and the cells, which all route through `setHover`.

- [ ] **Step 4: Run the tests and lint to verify they pass**

Run: `luajit tests/run.lua 2>&1 | tail -1 && luacheck . | tail -1`
Expected: `N passed, 0 failed` and `0 warnings / 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add UI/Grid.lua UI/MainFrame.lua tests/ui_smoke_spec.lua
git commit -m "feat: grid heading rows for the Legacy tab"
```

---

### Task 4: Fill the farm list, validate it, and update the docs

**Files:**
- Modify: `Data/Content.lua` (`LEGACY_WORLD_BOSSES`)
- Test: `tests/models_spec.lua` (a new "Content data" block)
- Modify: `docs/testing.md`, `docs/HANDOFF.md`, `README.md`

**Interfaces:**
- Consumes: the list shape from Task 1.
- Produces: nothing new.

- [ ] **Step 1: Write the failing data test**

```lua
describe("Content data", function()
  it("world boss lists are well formed", function()
    local ns = loader.load(loader.CORE)
    for _, list in ipairs({ ns.Content.WORLD_BOSSES, ns.Content.LEGACY_WORLD_BOSSES }) do
      local seen = {}
      for _, boss in ipairs(list) do
        assert.equals("number", type(boss.questID))
        assert.equals("q" .. boss.questID, boss.key)
        assert.equals("string", type(boss.name))
        assert(not seen[boss.key], "duplicate " .. boss.key)
        seen[boss.key] = true
      end
    end
    assert.truthy(#ns.Content.LEGACY_WORLD_BOSSES > 0)
  end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `luajit tests/run.lua 2>&1 | grep -E "Content data|passed"`
Expected: FAIL on `#LEGACY_WORLD_BOSSES > 0`.

- [ ] **Step 3: Source the IDs and fill `Content.LEGACY_WORLD_BOSSES`**

Start with the mount-dropping old world bosses that have a weekly loot lockout:

| Boss | Drop |
|------|------|
| Sha of Anger | Heavenly Onyx Cloud Serpent |
| Galleon | Son of Galleon |
| Nalak | Thundering Cobalt Cloud Serpent |
| Oondasta | Cobalt Primordial Direhorn |
| Rukhmar | Solar Spirehawk |

- For each boss, find its hidden weekly loot-lockout quest ID on Wowhead or wago.tools for patch 12.0.7.
- Write each entry as `{ key = "q<id>", questID = <id>, name = "<Boss>", drop = "<Drop>" }, -- <Boss>`.
- Leave out any boss whose ID you can't confirm from a source, and list it in the commit message as unsourced. Don't guess.
- Order the entries by expansion, then by name.

- [ ] **Step 4: Run the tests and lint to verify they pass**

Run: `luajit tests/run.lua 2>&1 | tail -1 && luacheck . | tail -1`
Expected: `N passed, 0 failed` and `0 warnings / 0 errors`.

- [ ] **Step 5: Update the docs**

- **`docs/testing.md`:** under the Legacy items, add:
  - Each listed boss's ID checks out with `/dump C_QuestLog.IsQuestFlaggedCompleted(<id>)`: `false` before a kill and `true` after.
  - The boss row shows a check only for the character that killed it, and clears at the weekly reset.
  - The "Raids" and "World bosses" headings show in blue and do nothing when clicked.
- **`docs/HANDOFF.md`:** in the architecture notes, record that the Legacy tab's rows carry a `kind` (`raid`/`boss`) or `heading`, and that `legacyBosses` is a record section.
- **`README.md`:** extend the Legacy sentence with "and a farm list of old world bosses that drop mounts".

- [ ] **Step 6: Commit**

```bash
git add Data/Content.lua tests/models_spec.lua docs/testing.md docs/HANDOFF.md README.md
git commit -m "feat: farm list of legacy world bosses, with a data check"
```
