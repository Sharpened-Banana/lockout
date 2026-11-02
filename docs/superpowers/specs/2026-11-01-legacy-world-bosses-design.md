# Legacy world bosses: design

Date: 2026-11-01. Extends `2026-10-30-lockout-addon-design.md`. That spec's Global Constraints still apply.

## Purpose

Farming mounts and transmog from old world bosses across a warband. The question it answers is "which of my alts can still kill this boss this week?". A short, chosen farm list is enough. Completeness across every expansion is not a goal.

## Decisions

- **Placement:** rows on the Legacy tab, below the older raids. The World Bosses tab stays current-season only.
- **Rows:** a fixed farm list from a data file. Every listed boss always shows, so an empty cell means that character can still go this week.
- **Detection:** each boss's hidden weekly loot quest, checked with `C_QuestLog.IsQuestFlaggedCompleted`. This is the same mechanism the current-season world bosses use. The saved world-boss list (`GetSavedWorldBossInfo`) is not used for these bosses, because it covers only some old bosses, needs a second ID per boss and returns localized names.

## Data

`Data/Content.lua` gains:

```lua
-- Old world bosses worth farming, in display order. Weekly loot lockout via a hidden quest.
-- Shape: { key = "q<questID>", questID = n, name = "...", drop = "..." }
Content.LEGACY_WORLD_BOSSES = { ... }
```

- `drop` is the notable reward, such as a mount name, shown in the tooltip. It's optional.
- Every quest ID comes from Wowhead or wago.tools for patch 12.0.7, with the boss name in a trailing comment. None are guessed. Each is verified in game with `/dump C_QuestLog.IsQuestFlaggedCompleted(id)` before and after a kill.
- Only bosses with a weekly lockout are listed. Rares with a daily loot lockout (for example Huolon) are excluded.
- Bosses that rotate weekly (Legion onward, only up while their world quest is active) may be listed, but the tab does not show whether one is up this week.

## Collection

`Collectors/WorldBosses.lua` also walks `Content.LEGACY_WORLD_BOSSES` in the same `Collect`:

```lua
record.legacyBosses[boss.key] = { name = boss.name, resetAt = Reset.Absolute(now, weekly) }
```

- The new `legacyBosses` section is separate from `worldBosses`, so legacy kills never appear as extra columns on the World Bosses tab, which lists every boss key it sees in `worldBosses`.
- `DB.Current` adds `"legacyBosses"` to its section list, so every record has the table. Older saved records gain it on the character's next login. No schema bump is needed: a missing section reads as no kills.
- Events, `requires` and debounce stay as they are. Like every collector, it is deferred in combat and runs in a `pcall`.

## Legacy tab

`UI/Tabs/Legacy.lua`:

- **Rows:**
  - A `{ heading = true, label = "Raids" }` row, then the older raid rows (unchanged).
  - A `{ heading = true, label = "World bosses" }` row, then one `{ kind = "boss", key = boss.key, label = boss.name, boss = boss }` row per farm-list entry, in data order.
  - A heading appears only when its group has rows. With an empty farm list and no older raids, the tab is empty, as today.
  - Raid rows gain `kind = "raid"`.
- **Cells:**
  - **Heading row:** `{ text = "" }`.
  - **Raid row:** unchanged (`Raids.LockoutCell`).
  - **Boss row, killed this week:** `{ text = Icon.check, color = green, title = boss name }`, with a tooltip of the drop (when set) and "resets in …".
  - **Boss row, not killed:** `{ text = "–", title = boss name }`, with the drop as the tooltip when set.
- **Columns:** unchanged (one per shown character).

## Grid and window

- **Heading rows** render in the accent color, with no zebra stripe and no hover tint. Clicking a heading row or one of its cells does nothing: `onRowClick` returns early for `row.heading`, ahead of the existing column-character lookup.
- Raid and boss rows behave as Legacy rows do today: clicking the name does nothing, and clicking a cell opens that column's character.

## Testing

Write each test first and watch it fail.

- **Collector** (`tests/weekly_collectors_spec.lua`): with quests stubbed, a completed legacy quest writes `legacyBosses[key]` with the weekly reset time, and `worldBosses` gains nothing from the legacy list. A list entry whose quest isn't complete writes nothing.
- **DB** (`tests/db_spec.lua`): `Current` creates `legacyBosses`, and fills it into an older record that lacks it.
- **Models** (`tests/models_spec.lua`):
  - Heading rows appear only for non-empty groups.
  - Boss rows always appear, in data order.
  - Boss cells show a check with the reset tooltip when killed, and "–" otherwise.
  - Expired kills read as not killed.
  - Heading cells are blank.
- **UI smoke** (`tests/ui_smoke_spec.lua`): heading rows show in the accent color, and clicking a heading row or its cells opens nothing. A boss cell click opens that character.
- **End to end** (`tests/e2e_spec.lua`): saved shapes without `legacyBosses` load and render without errors.
- **In game** (`docs/testing.md`): kill a listed boss, and its row shows a check for that character only, cleared at the weekly reset. Headings show and do nothing when clicked.

## Out of scope

- Showing whether a rotating boss is up this week.
- Rares with daily lockouts.
- A UI for editing the farm list. It lives in `Data/Content.lua`.
