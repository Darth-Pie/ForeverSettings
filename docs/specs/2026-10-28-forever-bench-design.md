# ForeverSettings Bench: an in-game graphics benchmark

Status: draft for the owner's review, 2026-10-28. Not committed: this folder is not a git repository, so the file is saved here and nowhere else.

## 1. Intent

The owner wants the best-looking picture that still holds 165 Hz at 3440x1440 (Radeon RX 9070 XT, Ryzen 9 7900X3D, 64 GB) in all WoW: Forever content, for personal use. Published advice (a video that tested a different PC) gives starting points, not this PC's costs. This piece measures them. It is the first of several pieces; only the benchmark is in scope here.

### Success criteria

1. `/fset bench check` prints the baseline mean frame time, the spread across repeated windows, and whether this spot is valid for benchmarking (not capped, not CPU-bound).
2. `/fset bench` produces, for each default setting, each tier's cost in milliseconds per frame relative to baseline, with average FPS, slowest-1% FPS and flags. It never prints a number for a window whose guard failed.
3. After every run (finished, stopped, aborted or crashed) every guarded CVar is back at its starting value, checked by reading it back. As an independent check, `config-snapshot.ps1 Diff` against a snapshot taken before the run reports no differences (run it after quitting the game, because Config.wtf is written on exit).
4. A default run of about 7 settings with about 5 tiers each takes about 7 minutes (section 6 gives the arithmetic).
5. Results persist in saved variables and can be read from the file after logout.

### Not goals (version 1)

An automatic tuner, a settings window with sliders or text entry (the menu in section 15 is the only UI), changes to how the forced list works, changing the FPS cap or vsync, automatic graphics restarts, exporting results, per-zone profiles, photo mode.

## 2. Decisions already made

- **In-addon runner.** The addon applies each tier, times frames and reports. Rejected: restarting the game per setting from the launcher script (every run needs a restart and a login). Manual marks survive only as a validation aid (`mark`, section 4).
- **Cost is reported in milliseconds per frame.** FPS gaps are not additive: 150 to 100 fps is 3.3 ms, 300 to 250 fps is 0.7 ms.
- **Frames are timed from `OnUpdate` elapsed, not from `GetFramerate()`.** `GetFramerate()` is smoothed and lags during drops ([GetFramerate](https://warcraft.wiki.gg/wiki/API_GetFramerate)). `OnUpdate` does not run on hidden frames and `elapsed` excludes time when the UI is not drawn ([OnUpdate](https://warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate)), so the timing frame is created without `UIParent` as its parent and stays shown.
- **Same API surface as ForeverSettings 0.1:** `GetCVar`, `SetCVar`, `InCombatLockdown`, `CreateFrame`, events, slash command, and the client's list of console commands when it has one (`C_Console.GetAllCommands`, or the older global `ConsoleGetAllCommands`; read only; see section 16). No memory access, no loading of outside code, no automation of play.

## 3. Architecture

Files: new `Bench.lua` (and `UI.lua`, section 15); small changes to `ForeverSettings.lua`; lines in `ForeverSettings.toc`. No new dependencies.

Both files share the addon's private table (`local ADDON, ns = ...`). `ForeverSettings.lua` exposes `ns.say(msg)`, `ns.db()` (the saved variables table), and `ns.suspended` (a boolean the bench sets while a run is active; `applyAll` returns at once when it is true). `/fset bench <rest>` is routed to `ns.bench.handle(rest)`. At the first `PLAYER_ENTERING_WORLD` after load, before the enforcement `applyAll`, `ForeverSettings.lua` calls `ns.bench.recover()`.

Units inside `Bench.lua`, each testable alone:

| Unit | Does | Depends on |
|---|---|---|
| `stats` | pure: mean, FPS, percentile, `summarize(dts)` | nothing |
| `guard` | pure: noise test, response test, background-cap suspicion, flag assembly | `stats` output |
| `plan` | builds the ordered list of windows from the settings table and discovered tiers | settings table |
| `restore` | snapshot the guarded set, restore in order, read back, report differences | `GetCVar`, `SetCVar` |
| `runner` | state machine driven by `OnUpdate` and events | all of the above |
| `report` | format the chat table, write history | saved variables |
| `handle` | the `/fset bench` subcommands | all of the above |

## 4. Commands

| Command | Does |
|---|---|
| `/fset bench check` | Preflight, then the baseline measured several times and the control test. Prints spread and a verdict. Uses the same snapshot, pending record and restore as a full run, because the control test changes a CVar temporarily. |
| `/fset bench` | Full run (section 6). |
| `/fset bench stop` | Abort now and restore. |
| `/fset bench list` | The settings table: CVar, whether it exists in this client, current value, tiers known. |
| `/fset bench probe <cvar>` | Discover and save a CVar's accepted tier values (section 9). |
| `/fset bench mark <label>` | Time one window now with the current settings and save it under the label, so a setting changed by hand in the menu can be compared with the runner's number. |
| `/fset bench report [n]` | Reprint the n-th most recent saved run (default: latest). |

## 5. Measuring one window

A window is a settle period (frames discarded) followed by a measurement period. `OnUpdate` `elapsed` values are appended to a preallocated array during measurement.

`summarize(dts)` returns: `n` (frames), `meanMs` = sum(dt) / n x 1000, `fps` = n / sum(dt), `low1Fps` = 1000 / the 99th-percentile frame time in ms (sorted ascending, index ceil(0.99 n)), `maxMs`, `hitches` (frames over 50 ms).

A window is valid only if `n >= MIN_FRAMES` and no frame is at or above `STALL`. A stalled window is retried once, then recorded as inconclusive.

Constants live together at the top of `Bench.lua` and are assumptions until measured on the owner's PC:

| Name | Value | Meaning |
|---|---|---|
| `SETTLE` | 3.0 s | discarded time after each change (covers shader compile and resource reloads) |
| `MEASURE` | 8.0 s | measured time |
| `MIN_FRAMES` | 200 | fewest frames for a valid window |
| `STALL` | 1.0 s | one frame this long invalidates the window |
| `NOISE` | 5 % | largest baseline drift before a setting's rows are suspect |
| `DRIFT` | 10 % | largest drift of a baseline bracket from the first baseline before a setting's rows are suspect |
| `SENSITIVITY` | 10 % | smallest frame-time drop the control must show |

`/fset bench check` exists to replace these guesses with this PC's actual spread before any sweep.

## 6. Run sequence

1. **Preflight.** Not in combat, not moving or falling. Refuse if a run is already active. If `db.bench.pending` exists from an earlier run, restore it first and say so (a second snapshot would record the changed values as the originals). Warn (do not change) if `vsync` is `1` or an FPS cap CVar is set, because a capped frame rate hides cost. Record zone, instance type, group size, resolution and render scale.
2. **Snapshot.** Capture the guarded set (section 8), add the settings under test and the control even if the console list omits them, and write it to `db.bench.pending` before anything is changed. Set `ns.suspended`.
3. **Control test.** Measure one window at the starting settings and one with the control CVar at a cheaper value. If frame time does not drop by at least `SENSITIVITY`, abort with "frame time did not respond to the control: capped or CPU-bound here". The control is render scale if that CVar exists, else the cheapest discovered tier of the shadow or lighting CVar. If no control is available the run stops and says to run `probe` first.
4. **Baseline B0.**
5. **For each setting S, in table order:** for each known tier value other than the current one: apply it, read it back, comparing numerically when both values parse as numbers so that `0.750000` equals `0.75` (a mismatch records "rejected, clamped to X" and skips the window), measure a window. After the last tier restore S to its original value and measure a baseline window B_i. If |B_i - B_(i-1)| / B_(i-1) exceeds `NOISE`, rerun S once from a fresh restore; if still noisy, every row of S is "inconclusive (baseline drifted X %)" and carries no delta. The row for the tier equal to the starting value reuses the mean of the two surrounding baselines. If the starting value is not a known tier, every tier gets a window and there is no reused row.
6. **Finish.** Restore the guarded set, read everything back, write the report and the history entry, clear `ns.suspended`.

Window count: sweep windows = sum over settings of (tiers - 1); baseline windows = 1 + settings; control windows = 2. At 11 s per window (`SETTLE` + `MEASURE`), 7 settings with 5 tiers each is 28 + 8 + 2 = 38 windows, about 418 s, about 7 minutes. Real tier counts come from `probe`. A noisy setting adds at most one extra pass of its own windows.

## 7. Validity guards

| Guard | Condition | Outcome |
|---|---|---|
| Combat | `PLAYER_REGEN_DISABLED`, or `InCombatLockdown()` at a step | abort, restore |
| Zoning | `PLAYER_LEAVING_WORLD` or `PLAYER_ENTERING_WORLD` during a run | abort, restore |
| Movement | `GetUnitSpeed("player") > 0` or falling, polled every 0.25 s | abort, restore |
| Stall | a frame at or above `STALL` | retry window once, then inconclusive |
| Too few frames | `n < MIN_FRAMES` | inconclusive |
| Control | frame time did not drop by `SENSITIVITY` | abort the run with the reason |
| Rejected tier | read-back differs from the value set | row marked rejected, no window |
| Noise | baseline drift over `NOISE` | rerun once, then inconclusive |
| Moved since the start | a baseline bracket differs from B0 by more than `DRIFT` | rows of that setting are inconclusive; the run goes on and later settings are checked the same way (a change that lasts moves every later bracket together, so neighbours alone would accept it) |
| No effect | every tier of a setting differs from baseline by less than `NOISE` x baseline | setting reported as "no measurable effect or not applied", never "free"; the report suggests checking it with `mark` |
| Background cap | median frame time between 30 and 36 ms with under 15 % spread between the 1st and 99th percentile | flag "possible background-window cap" |
| Game time | server time at a window start differs by 10 minutes or more from B0's | flag "lighting may have changed" |
| Other GPU load | not detectable | the preflight message tells the owner to close browsers, streaming and VR software |

A failed guard produces "inconclusive" or an abort, never a number.

## 8. Guarded set and restore

The guarded set is every CVar named in the client's list of console commands or in the built-in list of graphics CVars (section 16), for which `GetCVar` is not nil and whose lower-cased name contains any of: `graphics`, `raidgraphics`, `ground`, `shadow`, `ssao`, `giquality`, `light`, `liquid`, `water`, `texture`, `view`, `lod`, `horizon`, `farclip`, `sun`, `particle`, `weather`, `spell`, `render`, `fps`, `vsync`, `bloom`, `depth`, `compute`, `outline`, `projected`, `refraction`, `ripple`, `reflection`, `pbr`. The set is wide on purpose: changing a `graphics*` CVar can rewrite raw CVars derived from it (the forced `groundEffectDensity` is one), and the end state is only trustworthy if everything that can move is captured.

Restore order: the master presets (`graphicsQuality`, `RAIDgraphicsQuality`) first, then the other names beginning `graphics` or `raidgraphics` (any case), then the rest, each group alphabetical ignoring case, so a derived raw value is set after the menu-level value that rewrites it. A CVar is written only if its value differs at that moment, and the sweep puts the whole snapshot back after each setting, not only the setting it swept. Each `SetCVar` is wrapped in `pcall`. After the last one, every guarded CVar is read again and compared with its snapshot. Differences are printed ("could not restore X: was A, now B") and saved in `db.bench.lastRestoreIssues`. If a restore is due while the player is in combat it is queued until `PLAYER_REGEN_ENABLED`, and `pending` stays until then. `pending` is cleared after one restore attempt has been read back; the fallback for anything left over is `config-snapshot.ps1 Restore`.

Exit paths: finish, `stop`, any guard abort, an error (every `runner` step runs inside `pcall`; an error aborts and restores), and a reload, logout or disconnect (no event is guaranteed). `pending` was written before the first change, and the client writes the saved variables and `Config.wtf` together at those moments, so `ns.bench.recover()` finds it at the next login, restores, and says so. A hard crash writes neither file, so the files on disk still hold the starting values; that relies on the client not saving `Config.wtf` mid-run and is to be seen in the game.

## 9. Settings under test and tier discovery

| Setting | CVar | Status |
|---|---|---|
| Shadows | `graphicsShadowQuality` | name seen in the owner's Config.wtf |
| SSAO | `graphicsSSAO` | seen |
| Compute effects (fog) | `graphicsComputeEffects` | seen |
| Secondary lighting | `giQuality` or `graphicsLightMode` | both seen; which one the menu slider drives is unconfirmed. Decide by changing only that slider and running `config-snapshot.ps1 Diff` before adding it |
| Liquid detail | `graphicsLiquidDetail` | seen |
| Texture resolution | `graphicsTextureResolution` | seen |
| Ground clutter (menu) | `graphicsGroundClutter` | seen |
| Ground clutter (raw) | `groundEffectDensity` | seen; explicit tiers 48, 64, 128 (the video's values) |
| Render scale | `RenderScale` | name not confirmed in Forever; also the preferred control |

`probe <cvar>` finds a CVar's tiers: starting from 0, it sets each integer in turn up to a ceiling of 12, reads back, keeps the values that read back equal, stops at the first mismatch after at least one success, then restores the original. Discovered tiers are saved in `db.bench.tiers[cvar]`. A CVar with no tiers known, or that does not exist in this client, is skipped with a message. Raw CVars use explicit lists, never probing, because their ranges are large and a high value could stall the renderer (names are compared ignoring case). `probe` is refused while a benchmark is running, because it would change CVars inside a measurement window. It snapshots the guarded set first and puts the whole snapshot back afterwards, because a menu-level CVar can rewrite raw ones.

## 10. Interaction with the forced list

While a run is active `ns.suspended` is true and the enforcement `applyAll` does nothing, so the bench's own changes are not undone. The baseline is whatever the settings are at the start, including any forced values. After the restore the guarded set (which includes the forced keys) is back at its starting values, so no re-apply is needed. If `recover()` restored settings at login, it runs before the enforcement `applyAll`.

## 11. Output

Chat, per setting:

```
<Setting> (<cvar>)   baseline <ms> ms
  <value>  <ms> ms  <+/- delta> ms  <fps> fps  1% low <fps>  [flags]
```

History is saved in `db.bench.history` (last 10 runs): time, zone, instance type, resolution, render scale, baseline ms, rows (setting, value, meanMs, fps, low1Fps, maxMs, hitches, delta, flags), valid, reason. The saved-variables file is plain Lua, so the numbers can be analysed outside the game.

## 12. Testing

**Tested outside the client** (the same stub harness as ForeverSettings 0.1, extended with a simulated renderer whose frame times are a base plus a per-CVar-value cost):

- `stats`: mean, FPS, percentile and hitch counts on arrays with known answers.
- The runner recovers known costs within tolerance.
- A flat cost model (capped or CPU-bound) aborts at the control test.
- A combat event, a zoning event and movement each abort and restore.
- A saved `pending` at login is restored before enforcement.
- Restore order and read-back, with a stub where setting `graphicsGroundClutter` rewrites `groundEffectDensity`.
- A noisy baseline reruns once, then reports inconclusive.
- A setting with no effect is reported as "no measurable effect or not applied".
- A rejected tier (clamped read-back) is recorded and skipped.
- `ns.suspended` stops enforcement during a run.
- A thrown error mid-run restores.
- History is capped at 10.
- A second `/fset bench` during a run is refused and leaves `pending` untouched; a leftover `pending` is restored before a new run or check; a restore due during combat is deferred until combat ends; a run with no resolvable settings refuses cleanly.

Each guard gets a mutation control (remove it, confirm named tests fail), as for 0.1.

**Not testable outside the client, verified in the game:** real `OnUpdate` timing against the real renderer, behavior with the UI hidden, whether setting `graphics*` CVars changes rendering (some settings may need a graphics restart), whether `RenderScale`, `giQuality` and `graphicsLightMode` exist and what they drive, that the events used exist and fire as expected (`PLAYER_REGEN_DISABLED`, `PLAYER_LEAVING_WORLD`, `PLAYER_ENTERING_WORLD`; movement is polled, with no event), whether the client has a console command list at all and what shape it has (it did not in the Forever client; section 16), and saved-variable writes surviving a crash.

In-game verification steps:

1. `/fset bench check`: spread is printed and small, and the control responds.
2. `/fset bench list` and `probe`: names exist and tiers look right.
3. One setting changed by hand in the menu and timed with `mark` matches the runner's number for that tier within the spread.
4. Start moving mid-run: abort, restore, message.
5. After a full run, `config-snapshot.ps1 Diff before` reports no differences.
6. `/reload` mid-run, then log in: pending is restored and reported.

The test harness needs the `fengari` npm package and Node (already used for 0.1, kept in `C:\tmp\fset`, a temporary folder).

## 13. Unconfirmed and risks

- Names and behavior listed under "not testable" above. Each fails soft: a missing CVar is skipped with a message, not an error.
- A graphics change that needs a restart will show up as "no measurable effect or not applied". Automating restarts is a non-goal for version 1.
- Blizzard can clamp or remove graphics CVars between builds ([Forever Graphics Panel](https://www.curseforge.com/wow/addons/forever-graphics-panel) warns of this). The read-back check turns a silent clamp into a flagged row.
- Anti-cheat: only the documented addon API already used by 0.1. No claim beyond that, and nothing about Forever-specific rules.
- Constants in section 5 are guesses until `check` measures this PC.

## 14. Deferred pieces (not designed here)

A target-driven tuner that picks the best tier mix from the saved table, finer context profiles, a smart-drop guard, a stutter log with per-addon CPU through `C_AddOnProfiler`, frame pacing, photo mode.

## 15. In-game UI: minimap button, menu, report window (added 2026-10-28 at the owner's request; approved by the owner 2026-10-29)

The owner asked for an in-game UI and said a minimap dropdown menu is fine. This section adds one: a button on the minimap that opens a menu, and a small window for reports. It reuses the slash commands' code; the menu holds no logic of its own.

**Minimap button.** A round button parented to `Minimap`, draggable around its rim; the angle is saved in `db.ui.angle`. Left-click opens the menu. The tooltip shows the benchmark state ("idle", or "window 12 of 38") and the number of forced settings. `/fset minimap` shows or hides the button (saved in `db.ui.hidden`).

**Menu.** Built from a pure model, `ui.menuModel(ctx)`, rebuilt each time it opens:
- A title with the addon version.
- Forced settings: one submenu per entry, labelled `<cvar>: <value>` and marked when the current value differs. Each offers "Apply now" and "Stop forcing". Below them, "Apply all now" and "Restore everything the addon changed".
- Tiers: one submenu per resolved benchmark setting listing its known tiers, each labelled with the measured cost from the latest valid run when there is one (for example "3  +1.2 ms"). Choosing a tier forces that value, exactly as `/fset set <cvar> <value>` does.
- Benchmark: "Check this spot", "Run benchmark", "Stop" (enabled only while a run is active), "Show last report". Run and check are disabled in combat or while a run is active; a status line shows progress.
- Every action calls the same function as its slash command (`ns.command`, `bench.run`, `bench.check`, `bench.stop`).
- While a run is active the forced-list items, "Apply all now", "Restore everything" and the tier items are disabled, and the slash commands `set`, `unset`, `apply` and `reset` are refused with "benchmark running": the run owns the settings. Tier costs shown in the menu come from the newest valid full run and only from rows that carry no flag.

**Menu API.** The client's menu system is chosen when the menu opens: `MenuUtil.CreateContextMenu` if it exists, else the older `UIDropDownMenu` functions, else the click prints a one-line help. The model is tested; the two adapters are thin and are verified only in the game. Both are listed in the environment probes that `check` prints.

**Report window.** A small movable window with scrolling text that closes on Escape, showing the `bench.report(entry)` lines. "Show last report" opens it, and it opens by itself when a run finishes unless `db.ui.autoReport` is false (no UI for that setting in version 1).

**Not in this section:** sliders, text entry, a settings window, per-character UI settings.

**Testing.** Model tests cover idle, running, in combat, an empty forced list, differing values, tiers with and without a measured cost, and that each item's action reaches the right function. Three in-game steps are added to section 12: the button appears, drags and keeps its place after `/reload`; each menu entry works; the report window opens, scrolls and closes on Escape.

## 16. No console command list: the built-in CVar list (added 2026-10-29 after the first run in the game)

**What happened.** `/fset bench check` and `/fset bench` refused in the Forever client with `environment check failed: C_Console.GetAllCommands`. Sections 8 and 13 assumed the client could list its console commands; the probe showed it cannot, or not in the shape the code expected. The refusal was the designed one: nothing was changed. Every other probe passed (`GetUnitSpeed`, `IsFalling`, `GetGameTime`, `GetCVar` of an unknown name is nil, the menu API, `Minimap`).

**Fix.** The names the snapshot looks at come from two places, merged:
1. the client's list, when one works: `C_Console.GetAllCommands`, else the global `ConsoleGetAllCommands`; entries may be strings or tables with `command` (or `name`); a function that errors, or answers with something unusable or empty, counts as no list;
2. a built-in list (`ns.knownCVars`, 108 names) taken from the `Config.wtf` files of both installed clients (names only), filtered by the guarded substrings of section 8, plus `graphicsQuality`, `RAIDgraphicsQuality`, `RenderScale`, `useMaxFPS`, `maxFPS`, `maxFPSBk`.

A name in both appears once, spelt as the client has it; whether a name is a CVar in this client is still decided by `GetCVar` not being nil. The union means a partial client list cannot hide a setting, and the built-in list means a client with no list still gets a full snapshot. Tests hold the built-in list to three rules: unique ignoring case, every name guarded, and it covers every CVar of the settings table of section 9 and the master presets and frame-rate caps.

**Environment check.** The probe `C_Console.GetAllCommands` is replaced by `CVar list`: it passes when at least one guarded CVar exists, prints a note when only the built-in list was available ("the client has no list of its CVars; using the built-in list"), and fails only when no known graphics CVar exists at all.

**`/fset dump`.** Searches the same merged list, and says "this client has no list of its CVars; searching the built-in list of graphics settings" when only the built-in one exists. A CVar that is in neither list is still reachable by exact name with `/fset set`.

**What this does not cover.** A raw CVar that a menu-level write rewrites but that is in neither list would not be put back. The settings under test and the control are always added to the snapshot by name (section 6, step 2), so the settings the benchmark itself writes are covered either way; a stale built-in list could miss a derived CVar a later patch adds. `config-snapshot.ps1 Diff` after a run remains the check for that.
