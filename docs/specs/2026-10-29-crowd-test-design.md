# ForeverSettings: the busy-place test and the Crowded recommendation (piece B2), design

Date: 2026-10-29. Status: written for the owner's review; nothing is planned or built from it yet.

## 1. Intent

The novice mode (profiles spec, section 1) has three pieces: A profiles and undo, B guided tests and recommender, C the guided window. B1 (the quiet-spot recommender, `2026-10-29-recommender-design.md`) is built and installed. This spec is **B2**: a second, quicker test in a busy place that fills the **Crowded** profile, so a friend ends up with settings for everyday play (Everyday) and for raids, big dungeons, battlegrounds and busy cities (Crowded). It also adds a **Quick** mode to the quiet-spot test and a **check of the recommendation** to both tests. The reference point is Mac-ever (a Mac-only addon for the Forever client), whose test takes about 2 minutes in a busy spot; ours takes 10 to 15 minutes in a quiet one.

Decisions already made with the owner for B2 (2026-10-29, in the order asked):

- **The crowd test is quick and calibrated:** in the crowd each setting is measured only at its lowest level; the cost curves come from the quiet-spot test, scaled by how much more or less the lowest level saves in the crowd (section 5). It needs a valid quiet-spot result first.
- **The quiet-spot test gets a Quick or Thorough choice at its first screen,** Quick pre-selected and remembered. Thorough is today's test.
- **The crowd has its own target frame rate,** asked separately, 60 pre-selected, remembered separately.
- **The Crowded results button is "Save and switch"**, as for Everyday, with a line saying how to go back.
- **A crowd limited by the processor is a result, not an error:** the crowd test does not stop when a cheaper control setting fails to move the frame time.
- **The check of the recommendation is in both tests** (section 4.3).

Success for B2: after the quiet-spot test, a friend stands in a busy city for about 4 to 5 minutes and gets either a list of changes for Crowded with charts and one button, or a plain statement that nothing needs changing, that the crowd is limited by the processor, or that no steady reading was possible. Every figure says whether it was measured or estimated.

Not in B2: see section 11.

## 2. Facts this design rests on

- The quiet-spot test measures every level of each setting against bracketing baselines and stores rows with `deltaMs`, `current` and `starts` in `db.bench.history`; the recommender (`Recommend.choose`) turns them into a result with `changes`, `settings`, `nowMs`, `afterMs`, status `change`, `nochange`, `unreachable`, `nodata` or `invalid`, and the results window draws it.
- A measuring window now keeps settling until the frame time stops moving (3 to 15 s), so a baseline taken just after a change is no longer taken while the game reloads. The first live run (2026-10-29) showed that without this the first baseline and the ground-clutter and render-scale baselines were wrong, and that a repeated setting grows the window count.
- Noise limits today: 5% between bracketing baselines (`K.NOISE`) and 10% since the start (`K.DRIFT`). Profiles spec, section 1: "the crowded test needs a noise limit looser than the current 5%, to be calibrated in a real crowd."
- Crowds mostly add processor load, which graphics settings do not change; a cheaper `RenderScale` often fails to cut the frame time there, which the quiet-spot test treats as a stop (`control did not respond`).
- Mac-ever (read from its Wago and CurseForge pages on 2026-10-29, not run): a System Check of about 2 minutes, "stand still in a busy area, out of combat", measuring what each setting costs and keeping graphics as high as the goal allows.
- The player cannot run a test inside a raid or dungeon; a city's main square is the practical busy place.
- Manual switching only; the addon writes a setting only on a click, a typed command or a key press (profiles spec). The check of the recommendation writes settings temporarily inside the same guarded, always-restored machinery as the benchmark and is started by the click on Start, like the test itself.

## 3. What the player does

- **Order.** The crowd test builds on the quiet-spot test. The Everyday results window gains one line: `Next, in a busy place: Find my crowded settings (minimap menu or /fset crowd).`
- **Start.** A new menu item `Find my crowded settings` and the command `/fset crowd` open the guided window with kind `crowd`. If the history holds no valid setup entry (kind `setup`, valid, with rows), the window says `The crowd test builds on the quiet-spot test. Run Find my best settings in a quiet spot first, then come back here.` and offers only Close.
- **Quiet-spot first screen (change).** Two buttons under the target buttons: `Quick (about {N} minutes)` and `Thorough (about {N} minutes)`, each `{N}` from that mode's window estimate; Quick is pre-selected; the choice is saved in `db.ui.mode` when Start is pressed. Quick never recommends raising above the current level (the top level is not measured); Thorough can.
- **Crowd first screen.** Title `Find your crowded settings`. First line `This takes about {N} minutes. Stand somewhere busy, such as a city's main square, and leave the camera on a busy view. The game will change your graphics settings briefly to measure each one, then put everything back exactly as it was.` The target prompt reads `How smooth do you want it in crowds? Pick the frame rate you're aiming for.` with the six target buttons, 60 pre-selected, the choice saved in `db.ui.crowdTarget` when Start is pressed. Then the rules, the tick box and Start exactly as for the other kinds.
- **Running.** The guided window's Running view, unchanged, including the stop rules (movement, combat, zoning, stall, a forbidden window).
- **Results.** The results window with the title `Your crowded settings` for a crowd result. The button is `Save and switch` (or `Replace my Crowded and switch` when Crowded already holds values) and writes Crowded through `profiles.adopt("crowded", values)`. After it: `Crowded saved and switched on. Your original settings are kept: choose Everyday or Original in the minimap menu to go back, or use the key you bound to toggle Everyday and Crowded.`
- **A crowd limited by the processor** shows the existing `unreachable` sentence (the game is probably limited by something other than graphics settings, usually the processor) with the best estimate, and no apply button; it is never a stop.

## 4. Measuring

### 4.1 Quick mode of the quiet-spot test

The same sweep as today, but each setting is measured only at its lowest level, one middle level (the level at the middle position of the setting's list, other than the lowest and the current) and its current level; a setting with three levels or fewer is measured fully. The run takes `opts.levels = "quick"` or `"all"`. The window count includes the baselines and the control check (about 30 windows, about 6 minutes); `bench.estimateSetupWindows` takes the mode and the Intro shows the real estimate. Only measured levels are ever recommended, so no estimates are involved.

### 4.2 The crowd test (`bench.crowd`)

1. Preflight as today (no combat, no movement, no benchmark running). No `bench.learn`: the levels come from the quiet-spot entry.
2. A steady start: one baseline `B0` using the settle rule. The control stage is skipped; Render scale is measured like any setting, so a processor-limited crowd shows up as small savings.
3. For each setting that the quiet-spot entry measured (with a counted level below its live level), in the quiet-spot table order: set it to its lowest level, take one window `L`, put it back, take a baseline `B`. Each baseline is the "before" of the next pair, so `n` settings take `2n + 1` windows (17 for 8 settings, 3 to 4 minutes).
4. The saving of a setting is `mean(B before, B after) - L` (a drop in frame time), recorded as `lowDelta = L - mean(B before, B after)` (negative when the setting saves time).
5. Noise limits for crowds: a pair is inconclusive when its two baselines differ by more than `K.CROWD_NOISE` (15%) or when either has moved more than `K.CROWD_DRIFT` (30%) from `B0`; an inconclusive pair is repeated once (2 more windows) and then recorded as inconclusive. All four are named constants, guesses until measured in a real crowd (section 9).
6. The guards of the benchmark stay: movement, combat, zoning, stall, the forbidden windows, and everything is restored on every exit path with the same pending-record recovery.
7. The result is a history entry with `kind = "crowd"`, `valid`, `reason`, `baselineMs = B0`, `starts` (every setting's value at the start), `settings = { {cvar, setting, lowValue, lowDelta, baseMs, status, reason, flags} }`, `windows`, `reruns`. Crowd entries never feed the menu's tier costs or the Show-last-report item, which keep using the newest valid `setup` or full run.

### 4.3 The check of the recommendation (`bench.verify`), in both tests

After a recommendation with status `change` is worked out (section 5 for the crowd, `Recommend.choose` for the quiet spot), the guided window shows `Checking the result...` and calls `bench.verify(values, onDone)`: snapshot the guarded settings, write `values` (the changed settings only), take one window `V`, restore everything, take one closing baseline `E`. The measured frame time is scaled to the test's own baseline: `measuredMs = nowMs x V / E` (so a crowd that grew busier between the test and the check does not count against the recommendation). The result carries `verify = {predictedMs = afterMs, measuredMs}`. If the check stops for any reason the results show without it and say nothing about it. It takes about 30 seconds more and runs under the same stop rules; a stop restores everything first.

## 5. The Crowded recommendation (`Recommend.crowdEntry`)

One new pure function, `crowdEntry(quiet, crowd, options)`, builds an entry in the shape `Recommend.choose` already reads, so the greedy lowering, the ranking, the statuses and the charts are unchanged:

1. **Rebase the quiet-spot curves to the live levels.** For each setting present in both, take the quiet-spot rows (counted levels in order) and re-express every delta relative to the setting's live level (`crowd.starts[cvar]`): `delta'(level) = delta(level) - delta(live level)`. A live level that is not one of the measured levels is placed at its numeric position, with its delta interpolated linearly between its neighbours; outside the measured range the setting is not measured.
2. **Scale each curve by the crowd.** `factor = crowd lowDelta / delta'(lowest level)`, limited to between 0 and `recommend.CROWD_FACTOR_MAX` (4); a crowd `lowDelta` of zero or more (no saving) gives a factor of 0. The crowd delta of every level is `factor x delta'(level)`.
3. **A flat quiet-spot curve** (`abs(delta'(lowest))` below 0.05 ms) cannot be scaled; the crowd deltas then run in a straight line from 0 at the live level to `lowDelta` at the lowest level, by position among the levels.
4. **A setting measured in the crowd but not in the quiet spot** has only two levels: its live level (0) and its lowest level (`lowDelta`); it can be kept or lowered all the way.
5. **A setting with an inconclusive crowd pair, or missing from the quiet-spot entry's counted rows beyond its live level, is not measured** and stays as it is, listed with its reason.
6. The entry's `baselineMs` is the crowd's `B0`; its `starts` are the crowd's; `valid` and `reason` come from the crowd run; levels above the live level are kept in the rows (so the chart shows them) but Crowded never raises.
7. `Recommend.choose` is then called with the crowd target, `margin = recommend.CROWD_MARGIN` (0.10) and a copy of the ranking with every `raise` false. Statuses and sentences are those of section 4 of the recommender spec, with `Good news: your settings already hold {target} fps in crowds with room to spare. Nothing to change.` for `nochange` (the `{target}` is the crowd target).
8. The chart model's footer for a crowd result is `Each setting's lowest level was measured in this crowd; the levels in between are estimated from your quiet-spot test.` and the title is `Your crowded settings`.

## 6. The results window

- The same window and charts; the title, footer and apply target (`crowded`) follow the result's kind. The apply button writes the changed values only, through `profiles.adopt`, with the refusals (combat, a test running) of the recommender spec.
- A check line under the changes when `verify` exists: `Checked: expected about {X} fps, measured about {Y} fps.` and, when the measured frame rate is below 75% of the expected one, `The estimate was optimistic: about {Y} fps is what to expect.` The "With these changes" bar shows the measured frame rate when it exists, labelled `With these changes: about {Y} fps (measured)`.
- The Everyday results window gains the line of section 3.

## 7. Files

- `Recommend.lua`: `crowdEntry`, the constants `recommend.CROWD_MARGIN` (0.10) and `recommend.CROWD_FACTOR_MAX` (4), the crowd footer, title and `nochange` sentence in `choose` and `chartModel`, the measured-bar label.
- `Bench.lua`: `opts.levels` in `bench.run`; `bench.estimateSetupWindows(mode)`; `bench.crowd(quiet, onDone)`; `bench.verify(values, onDone)`; the constants `K.CROWD_NOISE` (0.15) and `K.CROWD_DRIFT` (0.30).
- `Guide.lua`: kind `crowd`; the Quick and Thorough buttons; the crowd target; the missing-quiet-spot message; the `Checking the result...` step before the results.
- `Results.lua`: titles, the check line, the measured bar label, the Crowded apply, the aftermath line, the Everyday results hint.
- `UI.lua`, `ForeverSettings.lua`: the menu item `Find my crowded settings` and `/fset crowd`.
- Saved in `ForeverSettingsDB.ui`: `mode` (`quick` or `thorough`), `crowdTarget`. History entries gain `kind`, `mode`, `verify`.
- `ForeverSettings.toc`: version 0.6.0; no new file, so `/reload` is enough.
- Tests: new `test/test_crowd.lua`; additions to `test_recommend.lua`, `test_bench.lua`, `test_guide.lua`, `test_results.lua`, `test_ui.lua`, `test_addon.lua`; `run.js` and `run_mutations.sh`.

## 8. Testing

Written test-first against the simulated game, each rule with a mutation check, as before:
- `crowdEntry`: the rebase (live level measured, live level between levels, outside the range), the factor (typical, clamped at 0 and 4, zero when the crowd shows no saving), the flat-curve line, a setting only the crowd measured, inconclusive settings listed, crowd baseline and starts used, never raising, the margin, and that the resulting `choose` statuses and sentences are right (including the crowd `nochange` sentence).
- `bench.crowd`: the window sequence (`2n + 1`), the setting set to its lowest level and put back, the pair arithmetic, the looser limits (a 10% drift is accepted in a crowd and refused in the quiet spot), the repeat of a drifted pair and nothing more, no control stage, a processor-limited crowd (small savings) completing, and every stop restoring everything.
- `bench.verify`: writes only the given values, restores in every case, scales to the closing baseline, a stop returns a failure with everything restored.
- Quick mode: only the lowest, middle and current levels are measured, small settings fully, the window estimate for both modes, and no recommendation to raise in Quick.
- The flow: the crowd Intro and its separate remembered target, the missing quiet-spot message, the Quick or Thorough choice remembered, `/fset crowd` and the menu item, the checking step and its failure, the hand-off, and that a crowd entry never reaches the tier costs or Show last report.
- The results window: the crowd title and footer, the Crowded apply, the check line and the optimistic line, the measured bar label, the Everyday hint.
- Not testable outside the game, checked there by the owner: how it behaves in a real crowd (steadiness, the noise limits, whether a city is quiet enough for the settle rule to finish), and the new buttons' layout.

## 9. Unconfirmed, and what the player gets if it is false

| Unconfirmed | If false |
|---|---|
| A crowd is steady enough for the 15% and 30% limits | Pairs come back inconclusive and are listed as not measured; if most are, the result is `nodata` (a plain "no steady reading" message), never a wrong recommendation. The limits are named constants. |
| The quiet-spot curve shape times a crowd factor estimates the levels in between | The estimate for in-between levels is off; the check of the recommendation (section 4.3) measures the real result and says so. |
| 10% headroom is enough for the crowd target | The player sees lower rates in a heavier crowd than the check; the margin is one named constant. |
| Standing still in a city is a good stand-in for a raid | A raid can be heavier; Crowded then falls short in some content. The check shows what the player got where they tested. |
| A setting measured only at its lowest level is a fair test | A setting whose lowest level behaves unlike its middle ones (a reload cost, for instance) is mis-estimated; the factor limit and the check bound the damage. |
| A cheaper `RenderScale` does not move a processor-limited crowd | If it does, the crowd is not processor-limited and the recommendation reflects that. |

## 10. Risks the design accepts

A busy place is the noisiest place to measure, so the crowd test deliberately takes few, paired measurements and says when it could not get a steady reading. The ranking is still a judgement about looks, and the crowd factor assumes the quiet-spot curve shape carries over. A friend who tests in a half-empty city gets settings tuned for a half-empty city; the intro says to stand somewhere busy and the results say where the test was done.

## 11. Out of scope

Testing inside a raid, dungeon or battleground; a multi-view test (turning the camera between phases); automatic switching by location; frame cap and VSync; named presets; the settings browser with descriptions and PC-only settings; picture looks (brightness, contrast, gamma); more than one crowd profile (raid versus battleground versus city); crowd results that raise settings; the friends' package (README, licence, changelog).
