# ForeverSettings: the guided benchmark window (piece C1 of the novice mode), design

Status: draft written 2026-10-29 for the owner's review. Not approved. No implementation has started.
Builds on: `2026-10-28-forever-bench-design.md` (the benchmark: check, run, restore, guards, report window, minimap menu) and `2026-10-29-profiles-design.md` (profiles). ForeverSettings 0.3.0 as installed on 2026-10-29.

## 1. Intent

The owner asked for a pop-up window that walks a player through a benchmark and, more important, tells them what NOT to do while it runs and while their settings are analysed. The addon is meant for friends who know nothing about graphics settings; a benchmark spoiled by an alt-tab, a step, or an opened menu wastes about nine minutes and gives wrong numbers. The owner's own first `/fset bench check` failed that way (baseline spread 38%, control four times slower) with only chat lines to explain it.

Success: a first-time player starts a check or a run, is told the rules before it begins and reminded while it runs, and when it stops for any reason is told in plain words why and what to do, and whether their settings were put back. A run that is broken by a rule the addon can detect stops at once and restores everything.

Decisions already made by the owner (2026-10-29):
- **Every start opens the window**: the minimap menu's Run and Check, and the typed `/fset bench` and `/fset bench check`. Nothing starts until the player clicks Start.
- **One tick box** must be ticked before Start works: "I have closed other programs and will stand still until it finishes".
- **Opening the game's settings, the game menu or the map during a run stops the run**, restores everything, and explains.

This is piece C1: only the guided benchmark flow. The "which settings should I use" results and recommendations (piece B) and the rest of the novice window (piece C) come later.

Not in this spec: automatic learning of each setting's values (`/fset bench probe` stays manual, see section 11), recommendations, an expert opt-out of the checklist, translations, sounds.

## 2. Facts this design rests on

- A run can stop, today, for these reasons (strings as the code emits them): `movement`, `combat`, `zoning`, `stall`, `few`, `no frames`, `stopped`, `control rejected`, `control did not respond`, `baseline <reason>` (the start window failed), `error: <message>`, `window busy`, `no snapshot`, `nothing to measure`, `no control`, and `preflight` with a list of problems: `a run is already active`, `you are in combat`, `you are moving or falling: stand still`, `environment check failed: <name>`. Warnings (printed only): vsync on, an FPS cap set, `restored an interrupted run first`.
- Flags on a measured row: `possible background-window cap`, `lighting may have changed`, `no measurable effect or not applied` (the third was missing from this list until the owner's first real run showed it as raw text); rows can be `inconclusive`.
- Results already reach a caller: `bench.run(onDone)` hands over the history entry (`valid`, `reason`, `rows`), `bench.check(onDone)` hands over `{ok, reason, baselineMs, spread, drop}`; a refused start hands over `{ok = false, reason = "preflight", problems = {...}}`. `bench.progress()` returns `{phase, label, done, total}` or nil. `bench.state().pending` is the saved record of an unfinished restore and `bench.state().lastRestoreIssues` the unrestored differences. `bench.stop()` ends a run safely.
- The measuring loop already polls every `K.POLL` (0.25 s of frame time) for movement and ends the window with a reason.
- The report window is built with `BasicFrameTemplateWithInset`, registered in `UISpecialFrames` so Escape closes it, and works in the owner's client. The minimap menu's "Run benchmark" and "Check this spot" call `ns.bench.run` and `ns.bench.check`; `/fset bench` and `/fset bench check` reach them through `bench.handle`.
- The addon cannot lock the keyboard or mouse. WoW gives addons no event for the game window losing focus (not found in the documented API; unconfirmed): alt-tab is only visible afterwards as a frame-time pattern (`possible background-window cap`).
- Policy: documented functions only (frame creation, `IsShown`, `OnUpdate`); nothing automated in gameplay; the window only warns and stops a run the player started.

## 3. The views

One window, title bar `ForeverSettings`, four views. Text below is exact unless it contains `{...}`.

**Intro** (`kind` run). Title `Test your graphics settings`. Lines:
`This takes about {N} minutes. The game will change your graphics settings many times to measure each one, then put everything back.`, then `Before you start:` with `- Stand still somewhere quiet, not a busy city.`, `- Close browsers, video, recording and streaming programs.`, `- Make sure you are not in combat.`; then `While it runs, do NOT:` with `- Move or jump.`, `- Open the game menu, the settings or the map.`, `- Switch to another window (alt-tab).`, `- Change any graphics setting.`, `- Log out or reload.` Tick box `I have closed other programs and will stand still until it finishes`. Buttons `Start` (enabled only when the box is ticked) and `Cancel`. `{N}` is `ceil(windows x (K.SETTLE + K.MEASURE) / 60)` from `bench.countWindows` for the resolved settings, and never less than 1.
**Intro** (`kind` check). Title `Check this spot`. First line `This takes about a minute. It checks that this is a good place to run the full test.`; the rest as above.

**Running**. Title `Testing your settings` (check: `Checking this spot`). A banner line `DO NOT MOVE OR OPEN ANY WINDOW`. Progress `Window {done} of {total}, about {M} minutes left` (when fewer than 60 seconds remain: `Window {done} of {total}, less than a minute left`; `M = ceil((total - done) x (K.SETTLE + K.MEASURE) / 60)`), and `Now testing: {label}`. With no progress yet: `Starting...`. One button, `Stop`. This view cannot be closed with Escape (section 5).

**Stopped**. Title `The test stopped`. Lines: the headline, the advice (section 4), an empty line, the restore line (section 6). Buttons `Try again` (back to the intro view, box unticked) and `Close`.

**Done** (run). Title `Finished`. Lines: `The test is finished.`, the restore line, then one line per notable flag (section 4), then, when rows are inconclusive, `{n} settings could not be measured reliably; they are marked in the report.` Buttons `Show report` (opens the existing report window for that entry; disabled when there is no entry) and `Close`.
**Done** (check). Title `Check finished`. `This spot is good for testing.` when `ok`, else `This spot is not good for testing right now.` followed by the reason's headline and advice; when `spread` is above `K.NOISE`, also `The frame rate was uneven here; a quieter spot gives better results.`; then the restore line. Buttons `Run the full test` (opens the intro view with `kind` run; only when `ok`) and `Close`.

## 4. Explanations (reason to words)

Every reason maps to a headline and advice; a reason with the prefix `baseline ` is explained as its inner reason with the headline prefixed `The test stopped at the start: `; an unknown reason gets headline `The test stopped (reason: {reason}).` and advice `Your settings were put back. Try again.` Never nothing.

| Reason | Headline | Advice |
|---|---|---|
| `a run is already active` | A test is already running. | Wait for it to finish, or press Stop. |
| `you are in combat` | You are in combat. | Leave combat, then try again. |
| `combat` | You entered combat, so the test stopped. | Leave combat, then try again. |
| `you are moving or falling: stand still` | You are moving. | Stand still the whole time, then try again. |
| `movement` | You moved, so the test stopped. | Stand still the whole time, then try again. |
| `environment check failed: {X}` | The game is missing something this test needs. | Tell the person who gave you this addon: {X}. |
| `zoning` | The game changed zone or reloaded, so the test stopped. | Stay where you are and do not reload, then try again. |
| `stall` | The game froze for a moment, so the test stopped. | Close other programs and try again. |
| `few` | The game ran too slowly to measure. | Close other programs and try again. |
| `no frames` | The game stopped drawing frames, so the test stopped. | Keep the game window in front, then try again. |
| `stopped` | You stopped the test. | You can start again any time. |
| `control did not respond` | The test could not tell the settings apart here. | This usually means the game window was not in front (alt-tab), or the frame rate is capped. Try again without switching windows. |
| `control rejected` | The game would not accept a settings change. | Close the graphics settings and try again. |
| `panel:settings`, `panel:menu`, `panel:map` | You opened the game's settings (the game menu, the map), so the test stopped. | Leave it closed while the test runs, then try again. |
| `window busy` | Another measurement was already running. | Wait a moment and try again. |
| `no snapshot` | The addon could not take a copy of your settings, so it did not start. | Nothing was changed. Tell the person who gave you this addon. |
| `no control` | This game has no setting the test can use to check itself. | Tell the person who gave you this addon. |
| `nothing to measure` | There is nothing to measure yet. | Some settings still need to be learned first: type /fset bench list to see which. |
| `error: {message}` | Something went wrong inside the addon. | Your settings were put back. Tell the person who gave you this addon: {message}. |

Flag lines on the Done view: `possible background-window cap` becomes `The game may have lost focus at some point (alt-tab?), so some results may be unreliable.`; `lighting may have changed` becomes `The time of day in the game changed during the test, which can affect lighting results.`; `no measurable effect or not applied` becomes `Some settings made no measurable difference in this spot; the report lists them.`; any other flag is shown as written. Each distinct flag appears once.

## 5. What it watches, and the closing rules

- **Watch hook.** `Bench.lua` gains one optional field, `bench.watch`: a function returning a reason string or nil. The movement poll calls it (inside `pcall`; an error counts as nil) after the movement test, in settle and measure phases, and ends the window with that reason (`ok = false`), exactly as movement does, so the existing abort and restore path handles it. With no `bench.watch` set nothing changes.
- **The guide's watch** returns `panel:settings` when the global `SettingsPanel` exists and `:IsShown()`, `panel:menu` for `GameMenuFrame`, `panel:map` for `WorldMapFrame` (checked in that order); a global that does not exist is skipped. The same check runs once when Start is clicked: if one is open the run does not start and the Stopped view explains.
- **Escape.** In the Intro, Stopped and Done views the window is in `UISpecialFrames` (Escape closes it: Cancel or Close). While Running it is removed from the list, so Escape cannot hide the banner (and Escape then opens the game menu, which the watch turns into a stop). `Stop` is the way out.
- **Alt-tab** cannot be prevented or detected as it happens; the window warns before and reports a flagged result after (section 4).

## 6. Start flow, routes and the restore line

- `guide.open(kind)` (`kind` is `"run"` or `"check"`): if a check, run or mark is active it shows the Running view, else the Intro view with the box unticked.
- `Start`: needs the box ticked and no forbidden panel open; calls `bench.run(cb)` or `bench.check(cb)`, sets `bench.watch`, shows Running. `cb` clears the watch and shows Done, or Stopped when the result is not ok (a `preflight` result shows its `problems`, one explanation each, the first as the headline). For a run, Done means the history entry has `valid` true and every other entry shows Stopped with the entry's `reason`. For a check, a result with `ok` true, or with `ok` false and the reason `control did not respond`, shows Done (that one is a finished measurement saying "not good here", not an interrupted one); every other not-ok result shows Stopped. The benchmark's own chat lines stay as they are.
- `Stop` calls `bench.stop()`. `Try again` goes to the Intro view. `Show report` closes the Finished window and then calls `ui.showReport(entry)` (the two windows overlapped and could not be told apart in the owner's first real run). `Run the full test` calls `guide.open("run")`.
- A run this window started does not open the report by itself when it finishes (`ui.runFinished` asks `guide.handlesReport()`); the report is offered on the `Show report` button. A run the window did not start still opens it as before.
- Progress totals include reruns: when a setting's closing baseline drifts and its sweep is repeated, the total grows by that setting's tier windows plus one baseline, so the count never reads "Window 47 of 45".
- Routes: `bench.handle("")` and `bench.handle("check")`, and the menu's Run and Check items, call `ns.guide.open("run" | "check")` when the guide is loaded and otherwise call `run` and `check` directly as today. `bench.run`, `bench.check`, `mark`, `probe`, `stop`, `list` and `report` are unchanged.
- Progress: while shown, the window reads `bench.progress()` every 0.5 s.
- **Restore line**, read from `bench.state()` after a stop or finish: `pending` is nil and `lastRestoreIssues` empty gives `Your graphics settings have been put back as they were.`; `pending` still set gives `Your settings will be put back when combat ends, or at your next login.`; a non-empty `lastRestoreIssues` gives `These settings could not be put back: {names}. Check them in the game's graphics menu.` The line is only said after reading the state, never assumed.

## 7. Files

- New `Guide.lua` (loaded after `UI.lua`): `guide.model(state, ctx)` (pure: the view's title, lines, banner, progress text, tick box, buttons with enabled flags, whether Escape may close it), `guide.explain(reason, detail)` (pure: headline and advice), `guide.restoreLine(state)`, `guide.panelReason()`, `guide.open(kind)`, and the thin frame adapter.
- `Bench.lua`: the `bench.watch` hook in the movement poll, and the two routes in `bench.handle`.
- `UI.lua`: the menu's Run and Check items call `ns.guide.open` when it exists.
- `ForeverSettings.toc`: one line for `Guide.lua` after `UI.lua`; version 0.4.0. Test side: the harness, `run.js` and `run_all.sh` learn the new file; new `test/test_guide.lua`.
- Existing tests that pin the current routes change and are named in the plan: the one that checks each `/fset bench` subcommand reaches its function, and the menu tests that spy on the Run and Check actions.

## 8. Testing

Written test-first against the simulated game, each rule with a mutation check, in `test_guide.lua`:
- The model per view: exact title and lines, the intro's `{N}` from a known window count, the tick box gating Start, Escape allowed in every view but Running, button sets per view, the progress text including the under-a-minute form and the no-progress form.
- `explain`: every row of section 4 by exact text; `baseline ` prefix; unknown reason. Each explanation is also checked against the real reason: drive each real stop (movement, combat, zoning, stall, few, no frames, stopped, control did not respond, control rejected, a panel opened) and assert the Stopped view's headline for the actual reason value, so a typo on either side fails.
- The watch hook: a stand-in open frame stops a run and restores everything; each of the three frames; a missing global is skipped; with no hook a run is unchanged; an error in the hook does not stop the run.
- The flow: Start disabled until ticked and with a panel open; Start calls run or check once; a refused start (combat, moving) shows its problem; Try again returns to an unticked intro; Done for a valid run, an invalid run and a check, with flag lines; the restore line in each of its three cases.
- The routes: `/fset bench`, `/fset bench check` and the menu items open the window and do not start anything; with the guide not loaded they call run and check directly.

Not testable outside the game, checked there: the text fits and looks right at the owner's UI scale; the buttons and tick box draw; the Escape behaviour; the three frame names and that each reads as shown when open.

## 9. Unconfirmed, and what the player gets if it is false

| Unconfirmed | If false |
|---|---|
| `SettingsPanel`, `GameMenuFrame` and `WorldMapFrame` are the names of those windows in this client | That rule never triggers and the run is not stopped by it; the window still lists the rule. The owner opens each mid-run in the game to confirm; a wrong name is a one-line fix. |
| `UICheckButtonTemplate` and `UIPanelButtonTemplate` exist | The adapter falls back to plain frames and a toggle button; the model and tests are unchanged. |
| Removing a frame from `UISpecialFrames` mid-run takes effect | Escape could hide the window mid-run; the run continues, `Stop` and `/fset bench stop` still work. |
| `IsShown()` is true at once when one of the windows opens | A window opened and closed between two polls (0.25 s) goes unnoticed. |
| The estimate (windows left x 11 s) | It cannot foresee a rerun until the drift is seen, so the total grows then (section 6) and the remaining time can be a little short; the text says "about". |
| WoW has no addon-visible signal for the game window losing focus | Alt-tab stays warn-before, flag-after, as in section 5. |

## 10. Risks the design accepts

A player can still ruin a run in ways the addon cannot see (a second program stealing the GPU, a long network spike). The checklist asks; the guards and flags catch what the frame times show. The window never claims a run was good without the guards agreeing.

## 11. Out of scope

Automatic probing: a first-time player still needs `/fset bench probe` for each setting before a full run has anything to measure (the run lists "no tiers known" and skips them). Running those probes for the player is the natural next slice and is not designed here. Also out: the recommendations screen (piece B), an expert opt-out, translations, sounds, a "do not show again" option.

## 12. Wording pass (2026-10-29, after the owner's first live run; the owner asked for a friendlier voice and chose the lighter version)

These texts replace the earlier ones in sections 3 and 6; everything else in section 3 is unchanged.

- **Intro rules (every kind).** `Before you start:` with `- Stand still somewhere quiet, not a busy city.`, `- Pick a view with some trees, water or buildings in it, and leave the camera there.`, `- Close browsers, video, recording and streaming programs.`, `- Make sure you are not in combat.`; then `While it runs, please don't:` with `- Move, jump or turn the camera.`, `- Open the game menu, the settings or the map.`, `- Switch to another window (alt-tab).`, `- Change any graphics setting.`, `- Log out or reload.` The tick box reads `I have closed other programs and will stay still, camera included, until it finishes`. (The camera lines answer a real question: the addon only notices the character moving, and a turned camera changes what is drawn, which makes a baseline drift.)
- **Intro first line for the setup kind.** `This takes about {N} minutes, so it's a good time to grab a drink. The game will change your graphics settings many times to measure each one, then put everything back exactly as it was.` (`minute` for exactly one.) The run and check kinds keep their first lines.
- **Running (every kind).** Banner `PLEASE DON'T MOVE, TURN THE CAMERA OR OPEN ANY WINDOW`. Progress `Step {done} of about {total}, roughly {M} minutes to go` (under 60 seconds left: `Step {done} of about {total}, less than a minute to go`; exactly one minute: `roughly 1 minute to go`), then `Now testing: {label}`, and, for a run or a setup (not a check), a third line `It runs on its own, so feel free to step away from the keyboard.` "About" is deliberate: a setting whose baseline drifts is repeated, so the total can grow. `Starting...` is unchanged.
- The Stopped and Done views and the explanation table of section 4 are unchanged: they were already plain and kind.
