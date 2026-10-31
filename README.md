# ForeverSettings

A World of Warcraft addon (Forever and retail clients) that finds good graphics settings for you and keeps them, without needing to know what any of them mean.

**Status: pre-release.** It is tested against a simulated game, not yet widely in the real one. See `CHANGELOG.md`.

## What it does

- **Find my best settings**: a guided test measures what each graphics setting costs in your game, then recommends settings for the frame rate you pick. The results window shows what each change does in frames per second and a **Save** button keeps the choice.
- **Find my crowded settings**: the same in a busy place (a city, a raid) for the settings you want there.
- **Profiles**, switched from the minimap button or `/fset profile`:
  - **Original**: your own settings, hands off. The addon records them before it first changes anything, and choosing Original puts them back.
  - **Everyday** and **Crowded**: settings you choose or save, put back at every loading screen.
  - **Maximum**: everything at its highest level the addon has learned. It needs plenty of graphics memory. It cannot be edited; it is worked out again each time.
- **My settings** (minimap menu): every setting with its levels, what each level costs in frames per second against the one you have, how much it matters to the picture, and what everything at the highest would give.

Nothing is forced on a first install. The addon never changes a setting in combat or while a test is running.

## Install

See `INSTALL.md` (for players). In short: unzip the release into the game's `Interface/AddOns` folder so that you have a folder named `ForeverSettings` there (for Forever: `World of Warcraft/_forever_/Interface/AddOns/ForeverSettings`), then start the game or `/reload`.

## Commands

`/fset` lists them. The ones you will use: `/fset profile everyday|crowded|maximum|original`, `/fset settings`, `/fset reset` (puts back everything the addon changed), `/fset minimap` (hide or show the button).

## Tests

The addon is Lua 5.1. The tests run under Node with [fengari](https://github.com/fengari-lua/fengari) against a simulated game (`tests/harness.lua`).

```
cd tests
npm install
bash run_all.sh --format-only     # TOC and file-format checks, seconds
node run.js . .. test_profiles.lua  # one suite
bash run_all.sh                   # every suite, then the mutation table (long)
```

`tests/run.js` also holds the mutation table: each rule in the code has a deliberate breakage that a named test must catch. `docs/specs/` holds the design specs.

## Packaging

Release zips are built with the [BigWigs packager](https://github.com/BigWigsMods/packager); `.pkgmeta` keeps `tests/`, `docs/` and `tools/` out of the zip.

## License

None chosen yet: all rights reserved until one is.
