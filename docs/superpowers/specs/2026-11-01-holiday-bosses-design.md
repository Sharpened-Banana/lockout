# Holiday bosses: design

Date: 2026-11-01. Builds on `2026-11-01-legacy-world-bosses-design.md` (the Legacy tab's heading and boss rows) and on `2026-10-30-lockout-addon-design.md`. Their Global Constraints apply.

## Purpose

Farming holiday-boss mounts and loot across a warband. The question it answers is "while this event is on, which of my alts haven't had today's holiday boss reward yet?". The bosses are the dungeon-finder holiday bosses, such as the Headless Horseman, Coren Direbrew, Apothecary Hummel and Lord Ahune. Each gives its loot to the first kill of the day.

## Decisions

- **Off-season:** a holiday boss shows only while its event is live. With no live event, there is no Holiday section.
- **Coverage:** whatever the game lists. While an event runs, the dungeon finder lists its holiday dungeon. Lockout reads that list, so it covers future holiday bosses with no IDs to maintain. Names come from the game, already localized.
- **Detection:** the dungeon finder, not hidden quests or the calendar.
  - The random-dungeon list, filtered by what the dungeon finder would offer, gives what's live.
  - The holiday flag, minus random-queue entries such as Timewalking, picks out holiday bosses.
  - Each dungeon's reward state gives "already looted today".
- **Reset:** daily (`C_DateAndTime.GetSecondsUntilDailyReset`). A kill expires at the daily reset, even for characters who are offline.

## Collection

New file `Collectors/Holidays.lua`, registered with the collector bus:

```lua
ns.RegisterCollector({
  name = "Holidays",
  events = { "LFG_UPDATE_RANDOM_INFO", "LFG_COMPLETION_REWARD" },
  requires = { "GetNumRandomDungeons", "GetLFGRandomDungeonInfo", "GetLFGDungeonInfo", "IsLFGDungeonJoinable",
               "GetLFGDungeonRewards", "RequestLFDPlayerLockInfo", "C_DateAndTime.GetSecondsUntilDailyReset" },
  OnLogin = function() RequestLFDPlayerLockInfo() end,
  -- A reward just landed; ask again so the next LFG_UPDATE_RANDOM_INFO carries doneToday.
  OnEvent = function(event) if event == "LFG_COMPLETION_REWARD" then RequestLFDPlayerLockInfo() end end,
  Collect = function(self, record, now) ... end,
})
```

`Collect` rebuilds `record.holidays` from scratch:

```lua
record.holidays = {
  active = { [dungeonID] = { name = name, resetAt = now + dailySeconds } }, -- listed holiday dungeons
  done   = { [dungeonID] = { name = name, resetAt = now + dailySeconds } }, -- doneToday is true
}
```

- **Walking the list:** `i = 1 .. GetNumRandomDungeons()`. `local dungeonID, name = GetLFGRandomDungeonInfo(i)`.
- **Holiday check:** a dungeon is a live holiday boss when all of these hold, and is skipped otherwise:
  - The 15th return of `GetLFGDungeonInfo(dungeonID)` (`isHoliday`) is truthy.
  - The 2nd return (`typeID`) is not 6, the random-queue type. Every Random Timewalking Dungeon carries the holiday flag, and the 18th return (`isTimeWalker`) is false for all of them on 12.0.7 (checked in the client during Hallow's End in a Warlords Timewalking week: the Horseman is type 1, Timewalking is type 6).
  - The dungeon finder would show it: `isAvailableForPlayer or not hideIfNotJoinable`, from `IsLFGDungeonJoinable(dungeonID)`. The random-dungeon list also holds inactive entries, which are marked hidden. This is the dungeon finder dropdown's own rule (`LFDFrame.lua`).
- **Done check:** `doneToday` is the first return of `GetLFGDungeonRewards(dungeonID)`.
- **Name:** the name from `GetLFGRandomDungeonInfo`, falling back to the first return of `GetLFGDungeonInfo`.
- **Unknown reset:** if `GetSecondsUntilDailyReset()` returns nil, `resetAt` is nil (`Reset.Absolute`). The UI must not do arithmetic on a nil `resetAt` (see Legacy tab).
- **New section:** `DB.Current` adds `"holidays"` to `SECTIONS`, and `Current` makes sure `holidays.active` and `holidays.done` are tables, as it does for other nested sections. No schema bump is needed: a missing section reads as nothing live and nothing done.
- **Collector rules:** like every collector, it is debounced, deferred in combat and run in a `pcall`. If an API in `requires` is missing, the collector disables itself and logs why.

## Legacy tab

`UI/Tabs/Legacy.lua`:

- **Live holidays:** the union, across every character in `ctx.db.characters` (not only the shown ones), of `Reset.Active(char.holidays.active, ctx.now)`, keyed by dungeon ID. When names differ, the first one found in a stable order wins (sorted by name, then ID). A live event belongs to the whole account, so a name filter must not hide it.
- **Rows:**
  - When at least one holiday is live: a `{ heading = true, key = "h:holidays", label = "Holiday" }` row first, then one `{ kind = "holiday", key = "hd:" .. dungeonID, dungeonID = dungeonID, label = name }` row per live holiday, sorted by name.
  - Then the existing Raids group and World bosses group, unchanged.
- **Cells (holiday row):**
  - The kill is `Reset.Active(col.char and col.char.holidays and col.char.holidays.done, ctx.now)[row.dungeonID]`.
  - **Looted today:** `{ text = Icon.check, color = green, title = name }`, with the tooltip `{ { left = name, right = "resets in " .. Util.Duration(resetAt - ctx.now) } }`, but only when `resetAt` is set. Otherwise there is no tooltip.
  - **Not looted:** `{ text = "–", title = name }`.
- **Clicks:** heading and cell clicks behave as for the existing Legacy rows. The grid needs no changes, because it already handles `heading` rows and Legacy cell clicks.

## Testing

Write each test first and watch it fail.

- **Collector** (a new `describe` in `tests/weekly_collectors_spec.lua`):
  - **Registration:** events and `requires` are as listed.
  - **Login:** `OnLogin` calls `RequestLFDPlayerLockInfo`.
  - **Holiday versus normal:** a holiday dungeon is written to `active`, and a non-holiday random dungeon is skipped.
  - **Done and reset:** `doneToday = true` adds a `done` entry. The reset time is `now + daily`.
  - **Rebuild:** the section is rebuilt from scratch, so stale entries are dropped.
  - **Missing API:** a missing `GetLFGDungeonRewards` disables the collector.
  - **Reward event:** `LFG_COMPLETION_REWARD` requests info again.
- **DB:** `Current` creates `holidays` with `active` and `done`, including on an older record without them.
- **Models** (`tests/models_spec.lua`, Legacy block):
  - **No live holiday:** the section is absent, and the existing rows are unchanged.
  - **Live, from a hidden character:** a holiday recorded active by a character that the filter doesn't show still appears.
  - **Expiry:** an active entry past its `resetAt` doesn't appear.
  - **Ordering:** holiday rows come before Raids.
  - **Cells:** a check with the reset tooltip for done. A check with no tooltip for done with nil `resetAt`. "–" for not done, for an expired done entry, and for a record with no `holidays` section.
- **UI smoke:** with one character's `holidays.active` seeded, the Legacy tab lists "Holiday" and the boss above "Raids". A cell click opens that character, and a heading click opens nothing.
- **End to end:** add the dungeon-finder stubs to the e2e install. Saved shapes without `holidays` load and render with no failures.
- **In game** (`docs/testing.md`):
  - During an event, the holiday boss appears under "Holiday".
  - After the first kill of the day, that character gets a check without a `/reload`, and the check clears at the daily reset.
  - Outside events, there is no Holiday section.
  - During a Timewalking week with no holiday event, there is no Holiday section.

## Out of scope

- Mount and loot drops in the tooltip, which would need sourced IDs.
- "Returns in N days" dates, which would need the calendar.
- Holiday bosses outside the dungeon finder, such as Winter Veil's Greench, and holiday daily quests.
- Holiday bosses on any tab other than Legacy.
