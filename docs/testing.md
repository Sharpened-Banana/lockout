# Manual in-game test checklist

Automated tests (`lua5.1 tests/run.lua`) and `luacheck .` cover the logic against a mocked WoW API. Everything
below needs the real client (Retail 12.0.x). Enable errors first:

    /console scriptErrors 1

## Setup

- [ ] Install the addon with its libraries (packaged zip, or a checkout plus the `.pkgmeta` externals under `Libs/`).
- [ ] Log in on two or more characters (different classes, ideally two realms) so the warband has data.
- [ ] `/lockout debug` shows no collector failures or "disabled: missing ..." lines on any character.
- [ ] A checkout in a folder named `lockout` (lower case, as on a case-insensitive filesystem) still loads: the
      window fills with data and `LockoutDB` is saved on logout.

## Window and persistence

- [ ] `/lockout` and `/lo` toggle the window; `Esc` closes it.
- [ ] Move and resize the window, `/reload`: position and size are restored (minimum size is enforced).
- [ ] Changing the scale in settings resizes the window immediately and survives `/reload`.
- [ ] Name filter narrows rows live; text such as `(` or `%` does not error.
- [ ] "Current realm only" checkbox filters rows and persists.
- [ ] Star a character: it pins to the top; sort by name, level and ilvl via the headers.
- [ ] Two characters with the same name on different realms display as `Name-Realm`.

## Lockouts

- [ ] Kill a raid boss: the Raids tab shows the new kill for that character, and the cell tooltip lists bosses
      as killed/alive with the reset time.
- [ ] After the weekly (or daily) reset, expired lockouts disappear without relogging; the data was not mutated
      (log in again, nothing reappears).
- [ ] Dungeons tab: a saved M0 dungeon shows a check, season-best M+ level appears per dungeon.
- [ ] World Bosses tab: a killed weekly boss shows a check with its reset tooltip.
- [ ] The Legacy tab lists each older raid any shown character is saved to as a row, with one class-colored column per character. The Raids tab shows only season raids.
- [ ] On the Legacy tab, the frozen column header reads "Raid" with no sort arrows, clicking a raid name does nothing, and clicking a cell opens that character's detail panel.
- [ ] Each listed Legacy boss's ID checks out with `/dump C_QuestLog.IsQuestFlaggedCompleted(<id>)`: `false` before a kill and `true` after.
- [ ] A Legacy boss row shows a check only for the character that killed it, and clears at the weekly reset.
- [ ] After looting a listed boss, its check appears without a /reload (it may take a moment after the kill).
- [ ] The Legacy tab's "Raids" and "World bosses" headings show in blue and do nothing when clicked.
- [ ] At the minimum window width, the five tab buttons don't overlap the "Current realm" toggle.
- [ ] Extended lockout: with reset = 0 the cell still displays sensibly (no "resets in 0s" or error).

## Weekly

- [ ] Vault tab columns show x/3 progress with reward item level; the Vault flag appears when rewards are waiting.
- [ ] After the weekly reset, a character with finished vault slots shows the Vault flag until it is claimed.
- [ ] Claim the vault and relog/refresh: the flag clears.
- [ ] Key column shows the owned keystone (`+level Dungeon`); rating matches the Mythic+ panel.
- [ ] Weekly best matches the Great Vault Mythic+ row tooltip after an over-time run.
- [ ] Delve currencies show with an "updated <age>" label (they do not reset).

## Gear

- [ ] Change a piece of gear: ilvl, upgrade track (for example "Hero 4/6") and enchant warnings update.
- [ ] A missing enchant on an enchantable slot is marked red; an empty socket shows the socket marker.
- [ ] Off-hand: enchant warning only when it holds a weapon, not a shield or held-in-off-hand item.
- [ ] Hovering a slot shows the item tooltip.

## Consumables and watchlist

- [ ] Detail panel groups consumables by category and counts bag items only (never bank or warband bank).
- [ ] Edit mode: untick a consumable and it hides (but is still scanned); the checkbox tick is clearly visible.
- [ ] Add a custom item by dragging it onto the drop zone, and by typing an item ID.
- [ ] Counts update after moving items in and out of bags (including the reagent bag).

## Detail panel

- [ ] Clicking a row (or cell) opens the panel; clicking the same row or the close button closes it.
- [ ] Header shows class/spec icon, name-realm, level, ilvl, gold and last seen.
- [ ] "Forget character" is hidden for the current character; for another it asks to confirm, then removes the
      character and closes the panel.
- [ ] At the minimum window size (640x320) the panel shows a scroll bar; the wheel and dragging the bar both reach
      "This week" and "Forget character". Leaving edit mode at the bottom does not leave blank space below the content.

## Minimap and settings

- [ ] The minimap button appears; left-click toggles the window, right-click opens the settings panel.
- [ ] The blue padlock icon (`Media/Icon.tga`) shows on the minimap button and in the AddOns list, not a green "missing texture" square.
- [ ] Tooltip shows "Vault ready: N characters" and "Highest key: +L Dungeon (Character)".
- [ ] `/lockout config` opens Options > AddOns > Lockout.
- [ ] The settings panel has: minimum level (1-90), show minimap button, window scale
      (0.7-1.5). Each change takes effect immediately; hiding the button hides it at once and persists across `/reload`.
- [ ] Test with the libraries absent (delete `Libs/`): no Lua error, `/lockout debug` shows "minimap libs missing",
      the window and `/lockout config` still work.

## Combat

- [ ] Entering combat does not cause collection errors; data refreshes after combat ends.
- [ ] During an active Mythic+ key, between pulls (out of combat, while Midnight's secret values restrict some APIs),
      looting, swapping gear and bag changes trigger collection with no Lua errors, and `/lockout debug` stays clean.

## Verify against the live client

These were assumptions made while building offline. Confirm each one and fix the code or data if it differs.

- [ ] `Content.ENCHANT_SLOTS` (Data/Content.lua) matches the enchantable slots in Midnight.
- [ ] Tooltip data (`C_TooltipInfo`): the upgrade-track line ("Upgrade Level: Hero 4/6") is found in a line's
      `leftText`.
- [ ] `C_Item.GetItemStats` EMPTY_SOCKET_* keys: confirm they appear only for empty sockets and that a filled
      socket does not count as empty.
- [ ] Textures resolve (no green squares): `auctionhouse-icon-favorite`, `UI-SortArrow`, `Interface\Buttons\UI-OptionsButton`,
      the ChatFrame size grabber, and class icon coordinates (`CLASS_ICON_TCOORDS`).
- [ ] Status markers (`Theme.Icon` in UI/Theme.lua) draw as icons, not blanks or boxes: the check
      `Interface\RaidFrame\ReadyCheck-Ready` (Dungeons and World Bosses cells), the vault-ready bag
      `Interface\Icons\INV_Misc_Bag_10` (Weekly "Vault" column) and the empty socket
      `Interface\ItemSocketingFrame\UI-EmptySocket-Prismatic` (detail panel equipment rows).
- [ ] Drag and drop onto the consumables drop zone receives the item (`GetCursorInfo`).
- [ ] The Forget confirmation popup passes the character GUID to `OnAccept` (the right character is removed).
- [ ] The edit-mode checkbox tick is visible.
- [ ] The Settings API calls in `UI/Settings.lua` behave as written: `Settings.RegisterAddOnSetting` argument order,
      `setting:SetValueChangedCallback`, slider labels, and `Settings.OpenToCategory(category:GetID())`.
- [ ] `.pkgmeta` externals (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0) all fetch during
      packaging (run the BigWigs packager and inspect `.release/Lockout/Libs`).
- [ ] Every ID in `Data/*.lua` resolves to the commented name once the tables are filled (see below).
- [ ] `/lockout debug` prints no failures after a full session.
- [ ] The Encounter Journal's world-boss pseudo-instance is filtered from the Raids tab. `Core/Season.lua` skips the
      raid entry named after the expansion (`EXPANSION_NAME<n>`); if Blizzard names it differently (for example after a
      zone), a stray raid column that is always empty appears. Note its name and filter it.

## Data still needed

These tables ship empty (`-- needs IDs`) because IDs must never be guessed. All features work with them empty, but
the matching UI stays blank until they are filled.

- `Data/Consumables.lua` `items`: default consumables (flasks, potions, food, runes, oils). Format is
  `[itemID] = "Category", -- Name (rank N)` using a category from `CATEGORIES`.
- `Data/Content.lua` `WORLD_BOSSES`: weekly world-boss quests. Format is
  `{ key = "q<questID>", questID = n, name = "Boss" }`.
- `Data/Content.lua` `DELVE_CURRENCIES`: delve currencies (keys, key shards). Format is `{ id = currencyID, name = "..." }`.

How to fill them:

1. Look the item, currency or quest up on Wowhead (or wago.tools) for the live patch (12.0.7) and note the ID.
2. Confirm in game:
   - items: `/dump C_Item.GetItemInfo(id)` (the first return is the name; it may be nil until cached, run it twice)
   - currencies: `/dump C_CurrencyInfo.GetCurrencyInfo(id)`
   - world boss quests: `/dump C_QuestLog.IsQuestFlaggedCompleted(id)` on a character that has (or has not) killed
     the boss this week; the result should flip when the boss dies.
3. Add the row with the name in a trailing comment, then run `lua5.1 tests/run.lua` and `luacheck .`.
