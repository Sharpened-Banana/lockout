# Lockout

Lockout is a World of Warcraft Retail addon that tracks, across your whole Warband, raid and dungeon lockouts, weekly progress (world bosses, Great Vault, Mythic+, delves), equipped gear and enchants, and the consumables you carry in your bags.

## Install

Download the packaged zip from a release and extract the `Lockout` folder into `World of Warcraft/_retail_/Interface/AddOns/`. To run from a source checkout instead, copy the repository folder there as `Lockout` and add the libraries listed in `.pkgmeta` under `Libs/` (the packager fetches them automatically for releases). The addon also runs without the libraries; only the minimap button is lost.

Log in on each character once so it appears in the Warband view.

## Usage

| Command | Action |
| --- | --- |
| `/lockout` (or `/lo`) | Toggle the window |
| `/lockout config` | Open the settings panel |
| `/lockout debug` | Print the internal log (collector failures, missing APIs) |

The minimap button toggles the window on left-click and opens settings on right-click; its tooltip shows how many characters have a Great Vault ready and the highest keystone in the Warband.

Tabs: Raids, Dungeons, World Bosses, Weekly and Legacy. Legacy lists older raids your characters are saved to, one row per raid with a column per character, a farm list of old world bosses that drop mounts, and, while a holiday event runs, its dungeon-finder boss with today's loot status. Click a character, or a Legacy cell, to open that character's detail panel (gear, enchants, consumables, this week).

## Development

Tests use a small built-in runner and a mock of the WoW API (busted is not required). Run them from the repository root:

    lua5.1 tests/run.lua                      # all specs
    lua5.1 tests/run.lua tests/some_spec.lua  # one spec
    luacheck .                                # lint, must report 0 warnings

Releases are packaged with the [BigWigs packager](https://github.com/BigWigsMods/packager) (`release.sh`), which reads `.pkgmeta` to fetch the libraries into `Libs/`.

The manual in-game checklist, the assumptions still to verify in the client and the data tables that need IDs are in [docs/testing.md](docs/testing.md).
