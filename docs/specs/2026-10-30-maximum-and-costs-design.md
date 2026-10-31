# ForeverSettings: a Maximum profile and the cost of every level (piece W3), design

Date: 2026-10-30. Status: design approved by the owner in three parts on 2026-10-30; this written spec awaits the owner's review. It follows W1 (`2026-10-30-words-and-menu-design.md`, 0.7.0) and W2 (`2026-10-30-results-window-design.md`, 0.8.0).

## Amendments (amended while planning; the owner approved them with the plan on 2026-10-30)

- A1. The note shown while Maximum is in use reads "You're using Maximum (everything at its highest). It includes the sharpest textures, which need plenty of graphics memory. Switch to Everyday or Crowded in the menu to change these.", followed, when some settings were left out, by "N setting(s) stay as they are: the addon has not learned their levels yet." It replaces the separate "Maximum is on..." line of section 3.2: after the Switch to Maximum click Maximum is in use, so this note is what the window shows.
- A2. While Maximum is in use the tabs behave as they do for Original: a tab click and a level click store into that tab's profile (not in use) as before. "Read-only" in section 3.2 meant that Maximum's own values have no edit path from the window.
- A3. A level's cost is measured against the held level: the row's selected level (the saved level; on the tab in use, the level in the game). A setting the tab holds no level for shows no costs.
- A4. The second line of a level button is a separate small font string under the button; a row with any cost text is 14 pixels taller.
- A5. `recommend.levelFps` and `recommend.estimateFps` call `choose(entry, 60)`; the target never matters to what they read.
- A6. A Switch to Maximum click that cannot proceed shows its reason in the window's red notice until the next click or redraw: the combat and busy sentences of the other buttons, or "Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do."

## 1. Intent

The owner's fourth request after the first in-game run: "a button in the menu that maxes out each setting to its max quality", because on a strong computer the frame-rate target is easily met and they would rather max everything; and "the tests should show the weight of benefit versus performance loss", so a player can see which level gives the best value ("level 5 is 10 fps faster than 6, but 6 is only 2 faster than 7"). W2 built the graphs of that cost. W3 puts it where levels are chosen and adds the maximum.

Decisions made with the owner (2026-10-30, one question each): Maximum is a **fourth profile**, not a button that edits Everyday or Crowded (Everyday, Crowded and Original are never touched; going back is a click on one of them); the cost view lives **in My settings, beside every level**, with a total at the bottom; Parts 1 to 3 of the design approved as presented.

Success for W3: from the menu a player puts every setting at its highest level in one click and gets back with one click; in My settings every level says what it costs against the level in use, each setting says how much it matters to the picture, and the window says what everything at the highest would give.

Not in W3 (section 8): measuring how a level looks, automatic best-value picking, a Maximum for crowds, any change to how the tests measure or to the recommendation rules.

## 2. Facts this design rests on

- A profile is Original plus its own values (`Profiles.lua`): `plan(name).writes` is Original's recorded values overlaid with the profile's; `switch` writes them, reads each back, sets `db.active` and `db.want` (the values re-applied at every loading screen). Original is read-only; Everyday and Crowded hold values in `db.profiles.<name>.values`.
- `bench.resolve()` lists the settings that have a CVar in this client and known levels (`tiers`, lowest first). My settings marks the last one "(highest)". A setting without learned levels is not in the list.
- `Recommend.choose(entry, target)` returns `settings[i].levels` with each level's `deltaMs` (frame time against the setting's own baseline at the test; the level the game was at has 0), `counted`, `current`. W2's graphs turn a level into frame rate as `1000 / max(nowMs + deltaMs, nowMs / MAX_SPEEDUP)` (`fpsAt`). `Recommend.RANKING[cvar].weight` (1 to 10) is the addon's own judgement of how much a setting matters to the picture.
- A Quick quiet-spot test measures each setting's lowest level, one middle level and the level in use; a Thorough test measures every level. So the cost of a level above the one in use is known only after a Thorough test. A crowd test measures only each setting's lowest level, and `Recommend.crowdEntry(quiet, crowd)` rebuilds crowd-adjusted curves from it.
- `guide.findQuiet()` returns the newest finished quiet-spot test; `ui.savedResult("crowded")` returns the crowd result (its `entry` is the rebuilt crowd entry) when there is one, with `measuredLine`. `Names.measured(zone, seconds)` gives "Measured in <zone>, <time> ago."
- The addon cannot see graphics memory. Texture sharpness at its highest is the one setting whose cost is memory rather than speed (`Names` says so; the recommender never raises it).

## 3. What the player sees

### 3.1 Maximum in the menu and in the commands

- The Profile section of the minimap menu lists **Original, Everyday, Crowded, Maximum**; the fourth tick reads **"Maximum: everything at its highest"**, and **"Maximum: everything at its highest (about 92 fps)"** when the newest quiet-spot test measured the highest level of every setting it knows (section 3.3). It is a tick like the others: ticked while Maximum is in use, greyed in combat and during a test, a click runs `/fset profile maximum`.
- `/fset profile maximum` and the menu tick call `profiles.switch("maximum")`. `/fset profile` lists it; the usage line and the unknown-name message name it: `usage: /fset profile [original | everyday | crowded | maximum | save <name> | raid on|off | toggle]` and `unknown profile 'x' (original, everyday, crowded or maximum)`.
- **What it sets.** Every setting in `bench.resolve()` is put at its highest level (the last of its `tiers`). A managed setting the client has but whose levels are not learned yet stays as it is. Chat after the switch (not silent): the usual `Profile: Maximum (N settings changed)`, then `Maximum includes the sharpest textures, which need plenty of graphics memory.`, then, when some settings were left out, `N setting(s) stay as they are: the addon has not learned their levels yet. Run Find my best settings once.` When nothing at all can be set: `Maximum has nothing to set yet: run Find my best settings once so the addon learns what each setting can do.` (and nothing changes; `db.active` stays as it was).
- **What it is not.** Maximum holds no saved values: they are computed each time it is switched to, and `db.want` (what is re-applied at every loading screen) is that same set, so it is enforced like any profile. It cannot be edited: `/fset set`, `/fset unset` and `/fset profile save` while it is in use, and `profiles.save`, `adopt`, `setProfileValue`, `unsetProfileValue` for it, refuse with `Maximum cannot be changed: it always holds every setting at its highest level. Pick Everyday or Crowded first.` and return the reason `"maximum"`; nothing is written. `/fset profile toggle` from Maximum goes to Crowded (as from any profile that is not Crowded). Crowded's raid option does not apply to it.
- **Going back.** Switching to Everyday, Crowded or Original writes that profile's values over Maximum's, and settings the profile does not hold go back to Original's recorded values (the existing `plan` rule). Leaving Original for Maximum records Original's values first, as for any profile.

### 3.2 My settings: the cost of every level, what it is worth, the total

- **Beside every level** (the buttons of a setting's row) a second line says what that level does to the frame rate against the level this tab holds (the saved level; on the tab in use, the level in the game): **`+8 fps`** (faster), **`-12 fps`** (slower), **`now`** for the level held, **`same`** when the difference rounds to less than 1 fps, **`?`** when that level was not measured. The difference is the level's frame rate minus the held level's frame rate, each as in W2's graph points (`fpsAt`), rounded to whole numbers. With no usable test, or when the held level was not measured, the second line is absent.
- **Which test.** The Everyday tab reads the newest quiet-spot test. The Crowded tab reads the crowd result's rebuilt entry when there is one, else the quiet-spot test. A line under the intro names it: `Costs from your quiet-spot test. Measured in Highmountain, 3 days ago.` or `Costs from your crowd test. Measured in Stormwind City, 2 hours ago.`; with no test: `Run Find my best settings to see what each level costs.`
- **What it is worth.** Under each setting's one-line description: **`Matters to the picture: a lot.`** (weight 9 or 10), **`some.`** (5 to 8), **`a little.`** (1 to 4), from `Recommend.RANKING`; a setting the ranking does not know has no such line. A note at the bottom says `"Matters to the picture" is the addon's own judgement, not something it measured.`
- **The total.** Above the buttons: **`Everything at the highest: about 92 fps.`** with a **Switch to Maximum** button (greyed in combat and during a test, with the window's usual one-line reason; absent while Maximum is in use). The estimate is `1000 / max(nowMs + sum of each setting's highest-level delta, nowMs / MAX_SPEEDUP)` over the settings the test measured, as in W2's "With these changes" bar, so it is an estimate (the steps overlap). It needs the highest level of every setting in `bench.resolve()` to be measured; otherwise the line reads **`The test skipped the highest levels of 3 settings, so there is no total yet. Run Find my best settings and choose Thorough.`** (`1 setting` in the singular) and, with no test, nothing (the line under the intro already says to run one). The button works without a total: the player may want Maximum anyway.
- **The click** runs `profiles.switch("maximum", true)` (silent) and the window then shows, where the intro's notice goes, **`Maximum is on. It includes the sharpest textures, which need plenty of graphics memory.`** (plus `N setting(s) stay as they are: the addon has not learned their levels yet.` when that applies); a refusal shows its reason in red like the Save button's.
- **While Maximum is in use** the window shows `You're using Maximum (everything at its highest). Switch to Everyday or Crowded in the menu to change these.` in place of Original's note; the tabs and rows are read-only exactly as they are for Original (a click writes nothing, per section 3.1).

### 3.3 The estimate in the menu

The Maximum item's text takes the section 3.2 estimate computed from the newest quiet-spot test (`guide.findQuiet()`), against the levels Maximum would set; no number when the section 3.2 conditions fail. It is read when the menu opens (`ui.buildContext`), never kept.

## 4. Rules and data

1. `Names.lua` gains `PROFILE.maximum = "Maximum: everything at its highest"` and `matters(weight)` (`"a lot"`, `"some"`, `"a little"` by the thresholds of 3.2), and the new texts of section 3 that are not in the files that print them; no game call.
2. `Recommend.lua` gains two pure functions: `recommend.levelFps(entry)` returns `{ nowFps, byCvar = { [cvar] = { { value, fps } ... } } }` (each counted level's frame rate as in W2's points; uncounted levels are absent) or nil for an invalid entry; `recommend.estimateFps(entry, values)` (`values = { [cvar] = level }`) returns `{ fps, ms, missing = { cvar... } }`, where `missing` lists the cvars in `values` whose level is not a counted level of the entry. Both use `choose`'s grouping and `fpsAt`; settings not in `values` contribute nothing.
3. `Profiles.lua`: `profiles.ORDER` and `LABEL` gain `maximum`; `profiles.maxValues()` returns `{ [cvar] = highest tier }` from `ns.bench.resolve()` plus the list of managed settings the client has that were left out; `plan("maximum")` builds `writes` from Original's values overlaid with those and `want` from those; the refusals of 3.1; the messages of 3.1. `db.profiles.maximum` is never created.
4. `Settings.lua`: `settings.model(st, ctx)` gains `ctx.costs` (`recommend.levelFps` of the tab's test and its source: kind, zone, seconds), `ctx.maximum = { fps, skipped }`, `ctx.active == "maximum"`; rows carry `matters`, levels carry `cost` (the second line's text); the model gains `costNote`, `totalLine`, the `maximum` button and the Maximum notice. The click key `maximum` runs the switch.
5. `UI.lua`: the Profile ticks gain `maximum`; `ui.buildContext` gains `maxFps`.
6. Version 0.9.0. No new file, so `/reload` is enough.

## 5. Tests and how each is verified

Written test-first with mutants in `test/run.js` and rows in `test/run_mutations.sh`: the cost arithmetic (held level measured or not, a faster and a slower level, the rounding to `same`, an uncounted level, the speed-up cap), the estimate (every highest level measured, one skipped, a setting not measured at all, the clamp), `matters` at each threshold, `maxValues` and the plan (levels learned, some not, none), every refusal of 3.1 writing nothing, going back from Maximum to each profile restoring exactly, the messages, the menu tick and its text with and without an estimate, the My settings model for each state (no test, Quick test, Thorough test, Crowded tab with and without a crowd test, Maximum in use, locked). The harness stubs cover the window's frames.

**No harness for:** how a second line fits the 100-pixel level buttons, the taller rows and the new bottom block. Verified only in the game by the owner's walkthrough and screenshots; the ledger says so.

## 6. Review focus (failure modes the tests above must pin)

1. Maximum with no learned levels, or some: no crash, nothing half-written, the plain message, `db.active` unchanged when nothing can be set.
2. Maximum then Everyday, Crowded or Original: every setting ends exactly where that profile puts it, including settings only Maximum touched.
3. `/fset set`, Save, Save and switch, a My settings click or a level click while Maximum is in use: refused, nothing written, no profile changed.
4. A level the game rejects or clamps while switching to Maximum: reported in plain words, the profile still active, nothing silently half-applied.
5. A Quick test, an old saved result (no `starts`), a crowd result, a held level that was never measured: costs show `?` or are absent and the total says what is missing; no error and no number that was not measured.

## 7. Release

0.9.0, installed as before (backup `pre-maximum`, `_forever_` and the retail copy). Owner's walkthrough: run Find my best settings as Thorough, open My settings and read the costs on both tabs; open the menu and read the Maximum item; switch to Maximum, look at the game, switch back to Everyday and to Original; check the texture memory line; screenshots of every state.

## 8. Out of scope

Measuring how a level looks (the benefit side is the addon's ranking words only); an automatic "best value" picker; a Maximum for crowds or raids; editing Maximum; per-level costs in the results window (its graphs already show them); any change to how the tests measure or to the recommendation rules.
