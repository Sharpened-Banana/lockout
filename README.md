# Lockout

Lockout is a World of Warcraft Retail addon that tracks, across your whole Warband, raid and dungeon lockouts, weekly progress (world bosses, Great Vault, Mythic+, delves), equipped gear and enchants, and the consumables you carry in your bags.

## Install

Download the packaged zip from a release and extract the `Lockout` folder into `World of Warcraft/_retail_/Interface/AddOns/`. To run from a source checkout instead, copy the repository folder there as `Lockout` and add the libraries listed in `.pkgmeta` under `Libs/` (the packager fetches them automatically for releases).

## Usage

Type `/lockout` (or `/lo`) in game to open the window.

## Development

Tests use a small built-in runner and a mock of the WoW API (busted is not required). Run them from the repository root:

    lua5.1 tests/run.lua                      # all specs
    lua5.1 tests/run.lua tests/some_spec.lua  # one spec
    luacheck .                                # lint, must report 0 warnings
