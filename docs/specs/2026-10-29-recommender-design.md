# ForeverSettings: the recommender for the empty spot (piece B1 of the novice mode), design

Date: 2026-10-29. Status: written for the owner's review; nothing is planned or built from it yet.

## 1. Intent

The owner wants a friend who knows nothing about graphics settings to end up with sensible settings for their own PC without reading a report. The novice mode was agreed as three pieces (profiles spec, section 1): A profiles and undo (built and installed), B guided tests and recommender, C the guided window (built and installed as 0.4.0). This spec is **B1**, the first slice of B: the recommender for the **empty spot**, with automatic learning of each setting's values. The crowded test and the Crowded profile are **B2**, a separate design to be written after the owner has measured in a real crowd, because its noise limit cannot be set before that (profiles spec, section 1).

Decisions already made with the owner for B1 (2026-10-29, in the order asked):

- **Scope:** the empty-area recommender first; the crowded test later.
- **Target:** the player picks a frame-rate target once, from a short list (60, 90, 120, 144, 165, 240), and the addon remembers it. For the owner it is 165 at 3440x1440 (bench spec, section 1).
- **Priority:** a built-in visual ranking decides which settings are cut or raised first (section 4); not cost only, not a style question.
- **Result:** one button saves the recommendation as the **Everyday** profile and switches to it. Nothing is ever written except on that click.
- **Charts:** the player sees bar charts of what each setting costs on their PC (section 5), because the owner asked to see the difference each setting makes.
- **Approach:** a greedy procedure over the ranking (section 4), not an exhaustive search and not fixed Low/Medium/High presets.

Success for B1: a first-time player picks a target, presses Start, stands still for about nine minutes, and gets either (a) a list of changes with charts and one button that applies them as Everyday, or (b) a plain statement that nothing needs changing, or (c) a plain statement of why no recommendation could be made. Every figure shown is from their own measurements and says "about" where it is an estimate.

Not in B1: the crowded test and Crowded profile; the raid graphics set; style preferences; changing the frame-rate cap or vsync; automatic switching of any kind; a step that re-measures after the switch (the first follow-up); translations.

## 2. Facts this design rests on

- The benchmark already measures every tier of nine settings against a baseline and stores rows in `db.bench.history`. A measured row carries `setting`, `cvar`, `value`, `baseMs`, `meanMs`, `fps`, `low1Fps`, `deltaMs` (relative to that setting's own bracketing baseline) and `flags`; a row that could not be measured carries `status` (`inconclusive` or `rejected`) and `reason`. The row for the tier the player already had is the "reused" row with `deltaMs = 0`. The entry carries `baselineMs` (the first baseline), `valid`, `reason`, `reruns` and `windows`.
- A rerun of a setting's sweep happens when its closing baseline drifts; it adds that setting's tier windows plus one baseline, and since 2026-10-29 the progress total includes them.
- The owner's real run in an empty spot (Highmountain, 2026-10-29, installed 0.4.0): baseline 2.98 ms (335 fps). Shadows tier 0 saved 0.87 ms, tiers 1 to 3 saved 0.19 to 0.27 ms, tier 5 cost 0.07 ms; SSAO tier 0 saved 0.50 ms; Compute effects tier 0 saved 0.23 ms; Liquid detail tiers 0 and 1 saved 0.21 ms; Texture resolution and both Ground clutter settings showed no measurable effect; Render scale was inconclusive (a baseline window read about 33 ms against 3 ms). An earlier run in Dalaran measured Render scale cleanly (baseline 3.83 ms, level 0.5 saved 1.16 ms). These numbers are the first test data.
- `bench.probe(cvar)` already finds a menu-level setting's levels (sets 0 up to a ceiling of 12, keeps those that read back equal, restores the original) and is refused in combat and during a run; raw settings (`groundEffectDensity`, `RenderScale`) have explicit level lists and are never probed.
- Profiles (spec 2026-10-29-profiles-design.md): Original is a captured, hands-off snapshot; Everyday and Crowded hold named values for the ten managed settings; the existing switch writes, reads everything back, and refuses in combat or while a run is active.
- The guided window (spec 2026-10-29-guided-benchmark-window-design.md) owns every start, stop rule and explanation; the report window opens only on request after a window-started run.
- Benchmark costs are frame times in milliseconds, which add; frame rates do not (bench spec, section 2). The benchmark measures speed, not how the picture looks, and not video-memory pressure.
- The addon is for the owner and friends: documented addon API only, manual switching only, nothing automated in gameplay.

## 3. What the player does

- **Start.** The minimap menu gets `Find my best settings`, and the command `/fset setup` does the same. It opens the guided window with kind `setup`. `/fset bench`, `/fset bench check` and the other commands are unchanged.
- **First screen** (kind `setup`). Title `Find your best settings`. A line `This takes about {N} minutes. The game will change your graphics settings many times to measure each one, then put everything back.` where `{N}` is the guided window's estimate with each setting that exists in the client but is not learned yet counted as 5 levels (4 windows measured plus 1 baseline) (amended while planning: A1, A5). A line `What frame rate do you want?` with six buttons `60`, `90`, `120`, `144`, `165`, `240`; the chosen one is shown pressed, and the last choice (saved in `db.ui.target` when `Start` is pressed) is pre-selected; with none saved, `Start` stays disabled until one is pressed. Then the same checklist, the same `do NOT` list and the same tick box as the guided window. `Start` needs a target and the tick.
- **Automatic steps after Start, with the guided window's Running view and stop rules unchanged** (moving, combat, opening the settings, game menu or map stops it; everything is put back):
  1. `bench.learn()` (section 6). It takes no frames of its own, so the Running view says `Starting...` (amended while planning: A1).
  2. The full sweep, exactly as `/fset bench` does today; it begins with its own control check, so there is no separate check run (amended while planning: A2).
  There is no separate capture of the player's Original settings: the existing switch captures the live values when it first leaves Original, and the run has put everything back by then (amended while planning: A3).
- **A setup run that ends valid** closes the guided window and opens the results window (section 5); there is no Finished window in between (they overlapped in the first real run). **A run that does not end valid** shows the guided window's Stopped view with its explanation; no results window.
- **After `Save and switch`:** a chat line `Everyday saved and switched on. Your original settings are kept: choose Original in the minimap menu to go back.`

## 4. The recommendation rules

One pure function, `recommend(entry, target, options)`, in `Recommend.lua`. It reads nothing from the game.

**Inputs.** `entry` is a history entry with `valid == true`; `target` is a frame rate; `options.margin` (default `0.20`) and `options.ranking` (the table below) can be overridden by tests.

**Which rows count.** A row counts only if it has a measured `meanMs` and `deltaMs` and none of the flags `possible background-window cap` or `lighting may have changed`. A row with `status`, or with either flag, is ignored and its tier cannot be chosen. A setting with no counted row besides its own current tier is `not measured`: it stays as it is and is listed. The flag `no measurable effect or not applied` does not exclude a row; its small measured deltas are used as measured.

**The budget.** `budgetMs = (1000 / target) x (1 - margin)`. At 165 fps and a margin of 0.20 it is 4.85 ms. The empty spot is the easy case, so the margin leaves room for busier everyday places.

**Ranking table** (weight: how much the setting matters to how the game looks, higher is cut last; and whether it may be raised above the player's current level):

| Setting | Weight | May be raised |
|---|---|---|
| Render scale (`RenderScale`) | 10 | yes |
| Texture resolution (`graphicsTextureResolution`) | 9 | no |
| Shadows (`graphicsShadowQuality`) | 6 | yes |
| Secondary lighting (`giQuality` or `graphicsLightMode`) | 5 | yes |
| SSAO (`graphicsSSAO`) | 3 | yes |
| Ground clutter, menu and raw (`graphicsGroundClutter`, `groundEffectDensity`) | 3 | no |
| Liquid detail (`graphicsLiquidDetail`) | 2 | yes |
| Compute effects (`graphicsComputeEffects`) | 2 | yes |

Texture resolution is not raised because its cost is video memory, which the benchmark cannot see and which shows up as stutter, not a lower average. Ground clutter is not raised because less clutter is often a visibility preference and not only a cost. A setting not in the table is left as it is.

A setting's levels are taken in the order the benchmark lists them and are assumed to run from lowest to highest quality (section 9).

**Procedure.**
1. For each measured setting, choose its start level: the highest counted level if it may be raised, else the highest counted level not above the player's current level.
2. Estimated frame time `E = entry.baselineMs + sum of the chosen levels' deltaMs`. Costs are assumed to add (section 9).
3. While `E > budgetMs`: each setting that has a counted lower level with a smaller `deltaMs` has a candidate move to the **nearest** such level (a lower level that is not cheaper is skipped). The move's `levels lost` is how many places the setting moves down in its ordered list of counted levels, and its `ms saved` is the drop in `deltaMs`. Make the move with the smallest `weight x levels lost / ms saved`; ties go to the lower weight, then to the order of the table. Recompute `E`.
4. If no setting can be lowered and `E` is still over the budget, the result is `unreachable`: no recommendation, and one of two texts (amended while planning: A4). When the lowest estimate is below the target: `Even the lowest settings are estimated at about {fps} fps, short of your {target}. The game is probably limited by something other than graphics settings, usually the processor.` When it is at or above the target but under the budget: `Even the lowest settings are estimated at about {fps} fps, which is not enough above your {target} to leave room for busier places. Try a lower target.` `{fps}` is `1000 / ms` rounded to a whole number.
5. If the chosen levels equal the player's current levels, the result is `nochange`: `Your settings already hold {target} fps with room to spare.`, no Apply button.

**Output.** `{ status = "change" | "nochange" | "unreachable", changes = { {cvar, setting, from, to, deltaMs} }, unchanged = {...}, notMeasured = {...}, nowMs, afterMs, nowFps, afterFps, budgetMs }`. `nowMs` is `entry.baselineMs`; frame rates are `1000 / ms`.

## 5. The results window

A new window `ForeverSettingsResults` (`Results.lua`), about 620 wide, movable, in `UISpecialFrames` so Escape closes it; `Not now` and the title bar's X close it. It is not the guided window and is only opened by the hand-off in section 3. `Recommend.chartModel(result, entry)` supplies every number; `Results.lua` only draws.

- **Chart A, before and after** (always visible, top). Two horizontal bars on one frame-rate scale from 0 to `1.2 x max(nowFps, afterFps, target)`: `Now: about {nowFps} fps` and `With these changes: about {afterFps} fps`, and a vertical line labelled `Your target: {target} fps`. Numbers are printed on the bars.
- **The changes**, one line each: `{setting} {from} to {to}, saves about {ms} ms` (or `costs about`); `{ms}` has one decimal, or two decimals below 0.1, so 0.4 reads `0.4`, 0.87 reads `0.9` and 0.07 reads `0.07` (amended while planning: A6, corrected while building: the first wording, "two when one decimal would show 0.0", would have printed 0.07 as `0.1`). For a result with no recommendation (nochange, unreachable) Chart A shows only the `Now` bar and the target line, and the per-setting charts show only the `now` marks (amended while building). For `nochange` and `unreachable` the section 4 sentence is shown instead and there is no Apply button.
- **Scrolling part: one chart per measured setting.** One bar per counted level, pointing left from a zero line labelled `now` when the level is faster than the current one and right when slower; the length is `abs(deltaMs)` on **one scale shared by all settings** (the largest absolute delta across them), so a setting that matters looks long and one that does not looks flat. The printed value is `-0.87 ms` or `+0.07 ms`. The current level is marked `now` and the chosen level `recommended`. A level that is not counted is greyed and says `not measured`. A setting with no counted level is listed as `not measured` with its reason.
- **Last line:** `Bars show speed on your PC in an empty spot, not how the picture looks.`
- **Buttons.** `Save and switch`: writes the recommended values into Everyday, with the current values for the settings it does not change, then switches with the existing verified switch. If Everyday already holds saved values the button reads `Replace my Everyday and switch`. In combat or while a run is active it is disabled and the reason is shown. `Not now` closes the window and changes nothing.

## 6. Learning each setting's levels

`bench.learn()` (in `Bench.lua`): for every row of `bench.SETTINGS` whose CVar exists and whose levels are not known (no explicit list and nothing in `db.bench.tiers`), call `bench.probe` on it; a probe that fails marks that setting `not measured` for this run with the probe's reason. It is refused in combat and during a run. It changes nothing that `bench.probe` does not already restore, so it needs no new restore rule. The guided window runs it as step 1 of section 3 under the same stop rules; if it finds no setting with levels, the run stops with the existing explanation `There is nothing to measure yet.` and says what to do.

## 7. Files

- New `Recommend.lua` (loaded after `Profiles.lua`, before `UI.lua`): `recommend`, `chartModel`, the ranking table, the target list.
- New `Results.lua` (loaded after `Guide.lua`): the results window, the only place that draws bars.
- `Guide.lua`: kind `setup` (first screen with the target buttons, the learning phase text, the hand-off).
- `Bench.lua`: `bench.learn()`; the reused row also carries `current = true`, so the recommender does not infer the player's level from a zero delta; `bench.handle("setup")`.
- `Profiles.lua`: one function that saves a computed set of values into Everyday and switches with the existing switch.
- `UI.lua`: the menu item `Find my best settings`.
- `ForeverSettings.toc`: the two new files; `## Version: 0.5.0`. New files need a full game restart, not `/reload`. `db.ui.target` holds the chosen target.
- Tests: new `test/test_recommend.lua`; additions to `test_guide.lua`, `test_bench.lua`, `test_profiles.lua`; `run.js`, `run_mutations.sh`, `run_all.sh` learn the new files.

## 8. Testing

Written test-first against the simulated game, each rule with a mutation check, as for the guided window.

- `recommend`, with the owner's real run (section 2) as one fixture and small invented tables for the rest: the budget at several targets and margins; the greedy order by `weight x levels lost / ms saved` and the tie-breaks; a setting that may not be raised starts at the current level; a setting that may be raised starts at its top level; rows with status or with either flag are never chosen; a setting with no counted row is `not measured` and unchanged; `nochange`, `unreachable` and `change` each reached; the estimate equals `baselineMs` plus the chosen deltas; `margin` and `ranking` overrides work.
- `chartModel`: bar lengths on the shared scale, the sign and label of each bar, the `now` and `recommended` marks, the before/after scale including the target line, greyed levels, the exact sentences of sections 3, 4 and 5.
- The flow: `/fset setup` and the menu item open the first screen and start nothing; `Start` needs a target and the tick; a saved target is pre-selected; `bench.learn` runs before the sweep and its failure becomes `not measured`; a valid setup run opens the results window and closes the guided one; an invalid one shows Stopped and no results; `Save and switch` writes Everyday with the right values, switches, and is refused in combat; `Not now` changes nothing; `Replace my Everyday` appears only when Everyday holds values.
- Not testable outside the game, checked there by the owner: how the bars and the scrolling frame draw and fit at the owner's UI scale; the readability of the labels; the unconfirmed items below.

## 9. Unconfirmed, and what the player gets if it is false

| Unconfirmed | If false |
|---|---|
| Each setting's levels run from lowest to highest quality in the listed order | The recommendation could lower the wrong end of a setting. The owner prints each setting's levels and compares them with the game's menu before any friend gets this; a setting whose order is reversed is a one-line fix in the ranking table (a flag to reverse it). |
| Costs add up (the estimate is a sum of separate measurements) | The "after" figure can be off by some tenths of a millisecond; it is labelled "about". The re-measure step (the first follow-up) is what tests it. |
| The 20% margin is enough for everyday places | The player sees lower rates in busy places than the estimate; Everyday is for general play and the Crowded profile (B2) is for crowds. The margin is one named constant. |
| Texture resolution and ground clutter should not be raised | A player with ample video memory misses a free quality gain. The two flags are in the ranking table. |
| Drawing bars from coloured rectangles in a scrolling frame works in the Forever client | The results window falls back to the written list of changes without charts (the drawing is guarded as in the guided window) and says so once. |
| `bench.probe` finds the levels of every menu-level setting in a friend's client, as it did in the owner's | A setting that cannot be learned is `not measured` and left as it is. |

## 10. Risks the design accepts

Frame times in an empty spot say little about a crowd, which is why B1 only fills Everyday and says so. The ranking is a judgement about looks, not a measurement. A friend whose game is limited by the processor will mostly get `unreachable` or `nochange`, which is the true answer, and the window says it in plain words and does not offer settings that would not help.

## 11. Out of scope

The crowded test and Crowded profile (B2, after the owner has measured in a real crowd); the re-measure step after the switch; style preferences; the raid graphics set; frame-rate cap and vsync; automatic switching; custom profile names; import and export; translations; the friends' package (README, licence, changelog).

## 12. Wording pass and live-run corrections (2026-10-29, after the owner's first live run)

- The setup Intro's first line, the target prompt (`How smooth do you want it? Pick your monitor's refresh rate, or the frame rate you're aiming for.`), the rules, the tick box and the Running view use the texts of section 12 of the guided window spec.
- Section 4, step 5: the `nochange` sentence is `Good news: your settings already hold {target} fps with room to spare. Nothing to change.`
- New outcome `nodata` (section 4): when no setting could be measured (every setting's baseline drifted, or the entry holds no rows) the result is `nodata`, never `nochange`: `The test couldn't get a steady reading here, so there is nothing to recommend. The frame rate kept changing between checks. Try again somewhere quiet, keep the camera still, and close other programs.` Chart A shows the Now bar and the target line; the only button is `Close`; the not-measured lines stay. (The first live run measured nothing and the window claimed the settings already held the target.)
- Section 6 and the benchmark: a measuring window keeps settling, slice by slice (1 s), until the last two slices' mean frame times agree within 10%, at least 3 s and at most 15 s, so a first baseline or a baseline after a reloading setting (Ground clutter, Render scale) is not taken while the game is still settling.
