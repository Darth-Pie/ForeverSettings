# ForeverSettings: plain words, a shorter menu and one "My settings" window (piece W1), design

Date: 2026-10-30. Status: approved 2026-10-30.

## Amendments (amended while planning)

- A1. The optional `quiet` argument of section 4 rule 3 is named `silent` in the code: `quiet` already means the quiet-spot test throughout the addon.
- A2. The per-level costs ("+0.6 ms") disappear with the Tiers section and `ctx.tierCost` is removed from `ui.buildContext`; costs return in W2/W3 as graphs read from the history.
- A3. "(lowest)" and "(highest)" are added only in the My settings window, where a setting's full level list is known; the results charts list only measured levels (a Quick test skips some) and show plain level text. Picture sharpness never gets marks.
- A4. The menu model marks a finished test with `done = true`; the two menu adapters draw the green check texture before the item's text, so the model's text stays plain.
- A5. Chart rows keep their raw `value` fields and gain `name` and `text` fields that the results window draws.
- A6. In combat or during a test the tabs of the My settings window are greyed with the other controls.
- A7. `/fset settings` and the menu item "My settings..." open the window; without the module both say `settings module not loaded`.

## 1. Intent

The owner ran the busy-place test (0.6.0) in the game on 2026-10-29 and asked for four things. They are too big for one design, so they are built in this order, each with its own spec and plan:

- **W1 (this spec): words and menu.** Plain-language names and explanations for every setting; the Forced settings and Tiers lists merged into one "My settings" window; the Benchmark section moved under Profile with green checks and saved results.
- W2: the report moves from chat into the results window, a "Save these as my X settings" button, and cost-versus-benefit line-point graphs.
- W3: a "max everything" button and the cost-versus-benefit view that goes with it.
- W4: the look (dark blue to purple gradients, not the stock game framing).

Who it is for: friends who know nothing about graphics settings. Every sentence a friend sees must make sense without knowing what a setting does. The raw setting names stay only where the owner looks (`/fset bench report`, `/fset dump`).

Decisions made with the owner (2026-10-30, one question each): build W1 first; one pop-up holds both the Forced settings and the Tiers lists; the pop-up has an Everyday tab and a Crowded tab; clicking a finished test's menu item opens its saved result; the developer items go under an Advanced submenu; the names table was approved as written in section 3.1.

Success for W1: a friend opens the menu, sees only plain words, runs the two tests from one short group, sees a green check on each test that has been run and can reopen and apply its result from the check, and can choose and keep individual settings in one window without meeting a technical name.

## 2. Facts this design rests on

- The menu today (UI.lua, `ui.menuModel`) lists Profile, Forced settings (one submenu per forced setting, raw names), Tiers (one submenu per measured setting, labelled with the benchmark's names such as "Ground clutter (raw)"), and Benchmark (status line, five test items, Stop, Show last report).
- A profile is Original plus its own values (Profiles.lua). `profiles.setValue` and `unsetValue` edit only the active profile and print to chat; `profiles.save(name)` copies the live values into Everyday or Crowded; `profiles.adopt` is the results window's button.
- Settings the addon manages: the nine measured settings (`bench.SETTINGS`; Secondary lighting resolves to `giQuality` or `graphicsLightMode`, whichever the client has).
- Test results live in `db.bench.history` (kept to 10 entries, `K.HISTORY`). The quiet-spot test saves its target in `db.ui.target`, the crowd test in `db.ui.crowdTarget`. A finished crowd entry holds rows only as settings, and the guided window rebuilds its result from the quiet-spot entry it ran on.
- The game's menu fonts have no check-mark character; the game ships the texture `Interface\RaidFrame\ReadyCheck-Ready`, which menu text can show inline.
- Adding a file to the TOC needs a full game restart; changing existing files needs only `/reload`.

## 3. What the player sees

### 3.1 The friendly names (one table, `Names.lua`)

| Today | Plain name | One line |
|---|---|---|
| Shadows | Shadow detail | How sharp and detailed shadows look. Higher looks better and costs a lot of speed. |
| SSAO | Soft corner shadows | Soft darkening where things meet, like corners and under objects. Small visual gain, moderate cost. |
| Compute effects | Extra effects detail | Extra effects the graphics card calculates. Hard to notice, moderate cost. |
| Secondary lighting | Light bounce | How light bounces around a scene. The new Forever lighting may change this one. |
| Liquid detail | Water detail | How detailed water and other liquids look. |
| Texture resolution | Texture sharpness | How crisp surfaces look up close. Costs graphics memory more than speed. |
| Ground clutter | Grass and plants | How much grass, flowers and small plants cover the ground. |
| Ground clutter (raw) | Grass and plants (exact amount) | The same thing with a finer dial: 48 is sparse, 128 is lush. |
| Render scale | Picture sharpness | 100% is full sharpness. Lower is faster but blurrier. |

The table is keyed by the setting's game name, and a lookup of any other name answers with that name unchanged. Level wording: Picture sharpness shows levels as percentages (0.5 is 50%); every other setting shows its number, with the lowest level marked "(lowest)" and the highest "(highest)". Profile names in the menu carry a plain subtitle: "Original: my own settings, hands off", "Everyday: normal play", "Crowded: raids and busy cities" (the commands keep their names).

The same names replace the raw ones in: the menu, the My settings window, the results window (labels and levels, including results saved before this version), the guided window's progress lines ("Now testing: Grass and plants (exact amount), level 48"; "Getting a steady starting speed"; "Checking the speed again after Shadow detail"; "Checking that the test works here"), and the chat messages the profile code prints about a setting.

### 3.2 The menu

```
ForeverSettings
Profile
  (tick) Original: my own settings, hands off
         Everyday: normal play
         Crowded: raids and busy cities
         Save my game's current settings as...  >  Everyday / Crowded
         [ ] Also use the Crowded settings in raids and battlegrounds
         (note, when the game's raid graphics are switched off: "The game's raid graphics are switched off, so this has no effect until you turn them on.")
Find my settings
         Find my best settings      (green check once run)
         Find my crowded settings   (green check once run)
         Stop                       (enabled only while a test runs)
         A test is running: step 5 of 17 (...)   (shown only while a test runs)
My settings...
Advanced  >  Check this spot, Run benchmark, Show last report,
             Apply all now, Put back everything this addon changed
```

The Forced settings and Tiers sections are gone from the menu. Test items are greyed in combat and while a test runs, as today.

### 3.3 Green checks and saved results

- "Find my best settings" has a green check when a finished quiet-spot test exists (`guide.findQuiet()` finds one) and `db.ui.target` is a listed target. "Find my crowded settings" has one when a valid crowd entry exists, the quiet-spot entry it was built on can be found, and `db.ui.crowdTarget` is a listed target.
- With a check, clicking the item opens the saved result in the results window (the same window, with the same Save and switch button). Without one, clicking starts the test as it does now.
- A result opened from the menu also says where and how long ago it was measured ("Measured in Highmountain, 3 days ago"; "just now", "N minutes ago", "N hours ago", "N days ago"; without a zone, "Measured 3 days ago") and has a **Run it again** button that closes the window and opens that test's guided window.
- A result opened this way shows the check line of the original run when one was made.
- A crowd entry records the time of the quiet-spot entry it was built on (`quietTime`), so reopening it rebuilds the same result even after the quiet-spot test was run again; when that entry is gone it uses the newest quiet-spot entry.
- The history cap never removes the newest finished quiet-spot entry or the newest finished crowd entry (when more than ten entries pile up, the oldest unprotected one goes).
- Reopened results describe the changes as of the test; applying them again is harmless.

### 3.4 The My settings window

- Title "My settings"; under it: "Choose how the game looks. Settings you tick are kept: the addon puts them back at every loading screen."
- Two tabs, **Everyday** and **Crowded**; it opens on the profile in use, which is marked "in use". Each tab has a one-line note ("Settings for normal play." / "Settings for raids and busy cities.").
- When Original is in use: "You're using your Original settings (hands off). Switch to Everyday or Crowded in the menu to turn these on." The tabs can still be edited; the values are saved for later.
- One row per setting the client has, in the order of section 3.1: a tick (Keep), the plain name, its one line, and a button for each level. On the tab in use the highlighted level is the game's live value; on the other tab it is that profile's saved value (none when it has none).
- Clicking a level ticks the row and sets it. On the tab in use it is applied at once and kept (through `profiles.setValue`); on the other tab it is only stored in that profile (new `profiles.setProfileValue`). Unticking stops keeping the setting (the game keeps its current value; stored for the other tab: removed). Ticking an unticked row keeps its current value (the live value on the tab in use; the game's current value as a starting point on the other tab).
- Footer: **Use what I have in the game now** (saves the game's current settings into the tab's profile, `profiles.save`) and **Close**.
- The window's own edits say nothing in chat (the row shows the result).
- Every control is greyed in combat and while a test runs, with the reason in one line ("You are in combat; try again afterwards." / "A test is running; try again afterwards."). The window refreshes about every half second, so a switch made from the menu or the key shows at once.
- It opens from the menu item, and `/fset settings`.

## 4. Behaviour rules

1. The pop-up never writes a profile except through a click on a row, a tick or "Use what I have in the game now".
2. An edit to the profile in use is applied through the same path as `/fset set`; an edit to the other profile writes only `db.profiles[name].values`.
3. `profiles.setValue`, `unsetValue` and `setProfileValue/unsetProfileValue` take an optional `quiet` argument; the window passes it, the slash commands do not.
4. Original is never edited: when it is in use the window shows the note in 3.4, and the Everyday and Crowded tabs stay editable.
5. Raw names are never shown by the menu, the pop-up, the results window or the guided window.

## 5. Files

- New `Names.lua` (pure: `ns.names.get(cvar)` returning name and line, `ns.names.label(cvar, fallback)`, `ns.names.level(cvar, value, position)`), loaded after `ForeverSettings.lua`.
- New `Settings.lua` (the window: a pure model and a thin frame layer, as in Guide.lua and Results.lua), loaded after `UI.lua`.
- `Profiles.lua`: `setProfileValue`, `unsetProfileValue`, `quiet` flags, names from `Names`.
- `UI.lua`: the new menu model; `ui.savedResult(kind)` (what the green check and the click use); `/fset settings` in `ForeverSettings.lua`.
- `Bench.lua`: the history keep rule; `quietTime` on crowd entries; progress carries the setting's name and level so the guided window words it.
- `Guide.lua`: progress lines from `Names`. `Results.lua` and `Recommend.lua`: labels and levels from `Names`; the age line and the Run it again button (`results.show(entry, target, verify, extras)`).
- `ForeverSettings.toc`: version 0.7.0 and the two new files (full restart needed).
- Tests: new `test_names.lua`, `test_settings.lua`; additions to `test_profiles.lua`, `test_ui.lua`, `test_guide.lua`, `test_results.lua`, `test_bench.lua`, `test_recommend.lua`, `test_addon.lua`; pinned tests that assert raw labels are rewritten, keeping their old lower-level assertion beside the new one.

## 6. Testing

Test-first against the simulated game, each rule with a deliberate-breakage check, as before:
- Names: every managed setting has a name and a line; an unknown name falls back unchanged; percentages for Picture sharpness; "(lowest)" and "(highest)" on the end levels only.
- Profiles: an edit to the other profile stores only and applies nothing; an edit to the profile in use applies; combat and a running test refuse before anything is written; quiet edits print nothing.
- The window: tabs and the "in use" mark; the Original note; ticks and level clicks on both kinds of tab; highlight source; disabled states and their one line; refresh after a profile switch; no chat output; `/fset settings`.
- The menu: order, no Forced or Tiers sections, the Advanced contents, the status line only while running, the check conditions, click behaviour with and without a check.
- Saved results: reopening hands the results window the right entry and target and the check line; the age line wording; Run it again opens the right guided window; the history cap keeps the two newest finished entries through ten crowd attempts; `quietTime` rebuilds the same crowd result.
- Words: no raw name in the menu, the window, the results window or the guided window's lines.
- Not testable outside the game, checked there by the owner: how the window looks and fits, and how the inline green check renders in the menu.

## 7. Unconfirmed, and what the player gets if it is false

| Unconfirmed | If false |
|---|---|
| Compute effects and Secondary lighting do what their one lines say | A friend reads a slightly wrong sentence; the owner corrects the table (one file). |
| Every level list runs from lowest to highest quality | A "(lowest)" mark lands on the wrong end for one setting; fixed per setting in the table. |
| The inline check texture renders in the game's menu | The item shows the texture path as text; the fallback is the word "(done)" in green, one line in `Names.lua`/`UI.lua`. |
| Nine rows, two tabs and a footer fit the window on small screens | The row list scrolls (the window uses a scroll area, as the results window does). |

## 8. Risks the design accepts

The window edits a profile that is not in use, which a friend may not expect; the "in use" mark and the tab notes carry that. Reopened results can describe changes already applied. Two new files mean a full restart for everyone updating from 0.6.0.

## 9. Out of scope (W2 to W4 and later)

Moving the report into the results window and the Save button (W2); line-point graphs, the max-quality button and the cost-versus-benefit view (W2/W3); the restyle (W4); any change to the tests' measuring; showing each level's cost in the My settings window; automatic switching by location.
