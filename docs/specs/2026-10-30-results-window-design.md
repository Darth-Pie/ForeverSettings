# ForeverSettings: results in the window, a Save button and cost graphs (piece W2), design

Date: 2026-10-30. Status: design approved by the owner in three parts on 2026-10-30; this written spec awaits the owner's review. It follows W1 (`2026-10-30-words-and-menu-design.md`, built and installed as 0.7.0).

## Amendments (amended while planning; the owner approved them with the plan on 2026-10-30)

- A1. A silent save would hide `switch`'s "stayed at" lines, so after a save whose `switch` reported mismatches the green line adds "The game kept N setting(s) at a different level than saved."
- A2. `chartModel` sets `model.saveKind` to `"changes"`, `"current"` or nil; `model.canApply` stays.
- A3. Axis rule: step = the smallest of 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000 with `ceil(max/step) - floor(min/step) <= 4`; from `floor(min/step)*step` to `ceil(max/step)*step`; while fewer than three ticks, widen one step above, then one below (not below zero), alternately. This replaces section 3.4's last axis sentence.
- A4. Points are spaced evenly by their position among the measured levels.
- A5. The changes column of the header shows at most 6 lines; with more, the sixth is replaced by "and N more changes: pick them in the list below."
- A6. The tag over the ringed point reads "now"; over the recommended point "recommended".
- A7. The footer keeps today's sentence and gains: "Each fps figure is that setting on its own; together they overlap, so the total is the number in the bars." (Everyday and crowd footers.)
- A8. The graph panel's title is "<Name>: fps if only this setting changes". A model graph entry carries `lines` (the step sentences, then the notices) in place of `steps` and `notice` of section 4.1.

## 1. Intent

The owner ran 0.6.0 and asked for four things; W1 delivered plain words and the new menu. W2 is the owner's items 2 and 4 (graphs):

- Chat after a test is "nonsense" for the friends this addon is for. Everything a friend needs goes into the results window, in plain words, on one screen.
- A button at the bottom of the results window reads "Save these as my X settings" (X = Everyday or Crowded), beside the Close button.
- Cost-versus-benefit **line-point graphs**: for a setting with several levels, show what each level costs, so a player can pick the level that gives the best bang for the buck ("level 5 is 10 fps faster than 6, but 6 is only 2 faster than 7").
- The window may grow a little in width and height.

Also fixed here: the results window sometimes opens scrolled (cause below), and the odd single readings (the owner's Ground clutter row) that make a curve look wrong.

Decisions made with the owner (2026-10-30, one question each): one graph at a time with a list of settings to pick from (not all graphs stacked, not a second window); with nothing to change the Save button still shows and saves what the game has now; Parts 1 to 3 of the design approved as presented.

Success for W2: after a guided test the chat holds no raw report; the results window shows the verdict, the bars, the changes in fps, one graph per setting on a shared scale, and Save / Run it again / Close, with nothing to scroll; a friend can save the result as their Everyday or Crowded settings from it, with or without a recommended change.

Not in W2 (see section 8): the max-everything button and the cost-versus-benefit view that goes with it (W3), the restyle (W4), any change to how the tests measure or how the recommendation is chosen.

## 2. Facts this design rests on

- After a guided test, `bench.run` and `bench.crowd` print to chat: the environment checks (`sayEnvironment`), warnings, "skipping ...", "close browsers ...", "run stopped: ...", and the whole raw report (`bench.report`, with setting names). The results window opens as well (Guide.lua `onDone` -> `ns.results.show`).
- `Results.lua` (384 lines) is 680 by 480, draws bars from `Recommend.chartModel` and puts the per-setting bars in a `ScrollFrame`. It never resets the scroll position when it draws, and it places paragraphs from text-height estimates; either can leave the scroll area starting partway down, which is the likely reason the window opened scrolled (the cause was not confirmed in the game; removing the scroll box removes it either way).
- Its button "Save and switch" (or "Replace my Everyday and switch") exists only when a change is recommended. Otherwise only "Close" shows.
- Every level a test measured has `deltaMs`, the frame time difference against that setting's own baseline; the level the game was at has `deltaMs = 0` (`Recommend.group`, `addCurrent`). `entry.baselineMs` is today's frame time. A level counts (`counted`) unless it carries an unusable flag or no measurement. Rows also carry `hitches`, `low1Fps` and flags.
- `profiles.adopt(name, values)` lays `values` over the live managed settings, stores them in the profile and switches to it; with `values = {}` it stores what the game has now. It, and `profiles.switch` which it calls, print chat lines. W1 gave `setValue`, `unsetValue` and `save` an optional `silent` argument.
- The guided window already has plain words for every stop reason it can show (`guide.explain`), so the chat copies of those reasons are redundant in a guided test. It does not mention the two warnings that matter to a friend: vsync on, and a frame-rate cap (the test cannot see costs above the cap). Those are chat-only today and use setting names.
- Adding a file to the TOC needs a full game restart.

## 3. What the player sees

### 3.1 Chat after a guided test

A guided test (Find my best settings, Find my crowded settings, and the check of a recommendation they run) prints nothing to chat while it runs or when it ends, except:

- safety messages: `in combat: your settings will be restored when combat ends`, `could not restore ...`, `restored settings from an interrupted benchmark`, `restore failed ...`;
- two warnings, reworded: **"Vsync is on, so your frame rate is capped at your screen's refresh rate and the test cannot see what settings cost. Turn vsync off in the game's graphics options and run the test again."** and **"A frame-rate limit is set in the game, so the test cannot see what settings cost above that limit. Raise or remove the limit and run the test again."** (neither is changed automatically); and "Settings from an interrupted test were put back first.";
- the fallback of the results window when it cannot be drawn (as now).

What is silenced: environment lines, "skipping ...", "close browsers ..." (the guided window's first screen already says it), "run stopped: ..." and "cannot run: ..." (the guided window shows the stopped view with the reason in plain words), "nothing to measure", "no control setting ...", and the raw report. The same commands typed on the keyboard (`/fset bench run`, `/fset crowd`, `/fset bench check`, `/fset bench report`) and the Advanced menu items print everything as before, with the two warnings in their new words.

### 3.2 The results window

Size 760 by 540 (was 680 by 480). No scroll box. From the top:

1. Title: "Your best settings" or "Your crowded settings".
2. One verdict sentence. A recommendation: "This change should take you from about 120 fps to about 165 fps." or "These N changes should take you from about X fps to about Y fps." (the measured figure when the check ran, else the estimate). Nothing to change, no steady reading, or target out of reach: the sentences the recommender already gives (`result.summary`).
3. The bars: Now, With these changes (when there is a recommendation), Your target. Unchanged.
4. The changes, one line each, in fps: "Shadow detail: High to Medium, saves about 12 fps." The figure is what that setting does on its own (`1000 / (nowMs + toDelta - fromDelta) - nowFps`, rounded; "less than 1 fps" below 0.5); a raise reads "costs about N fps". The footer says that figures are per setting and overlap, so the total is the bar's number.
5. The check line ("Checked: expected about ..., measured about ...") and the line "Measured in <zone>, <time> ago." as now, when present.
6. The graph area (3.4).
7. The footer text of today, and the buttons (3.3).

### 3.3 The buttons

Left to right: **Save**, **Run it again** (only on a result opened from the menu or a guided test, as now), **Close**. Widths 250, 150, 150 with 12 pixels between, centred.

| result | Save button |
|---|---|
| a change is recommended | "Save these as my Everyday settings" (Crowded for a crowd result); "Replace my Everyday settings with these" when the profile already holds values. Stores the recommended values and switches the profile on, as `profiles.adopt(profile, changedValues)` does today. |
| nothing to change | the same text. Stores what the game has now and switches the profile on (`profiles.adopt(profile, {})`). |
| target out of reach, no steady reading, invalid | hidden: there is nothing worth saving |

Close is "Close" (was "Not now" when a change was on offer). The button is greyed with the usual one-line reason in combat and while a test runs (`You are in combat; try again afterwards.`, `A test is running; try again afterwards.`). A click that is refused (combat, busy) shows the reason in the red notice line and writes nothing.

After a successful save: no chat line. The window stays open; the Save button is hidden; a green line says **"Saved as your Everyday settings and switched on. Your original settings are kept: choose Original in the minimap menu to go back."** (for Crowded: **"Saved as your Crowded settings and switched on. Your original settings are kept: choose Everyday or Original in the minimap menu to go back, or use the key you bound to toggle Everyday and Crowded."**). `adopt` and `switch` take W1's optional `silent` argument and say nothing when it is true; their refusals still return the same reasons.

### 3.4 The graph

Below the changes, left to right: the **setting list** (210 wide), then the **graph panel** (the rest).

- **List.** One row per measured setting, 22 pixels high, plain name, ordered by swing (highest fps minus lowest fps among its points) from large to small. A coloured dot marks a setting the test changes. The selected row is highlighted; a click selects. Settings that could not be measured follow, greyed; selecting one shows its reason in the graph panel instead of a graph. At most 12 rows (the names table has 10 settings). The first changed setting is selected when the window opens, else the first row; the selection survives redraws of the open window.
- **Panel title**: "<Name>: about N fps if only this changes" with the name in plain words.
- **Points.** One point per measured level (`counted`), in level order, lowest on the left. The height is `fps = 1000 / (nowMs + deltaMs)`. A line joins neighbouring points. A level the test did not measure (a Quick test skips some) has no point. The level the game is at is ringed and labelled "now"; the level the test picked, when it differs, is labelled "recommended" in the recommendation colour. The lowest and highest measured level are labelled under the axis with their plain level text (picture sharpness shows percentages, as in W1); the other levels are labelled only when they are the current or recommended one.
- **Scale.** One fps scale for every graph, so a setting that matters looks steep and one that barely matters looks flat. The axis shows three to five round numbers (steps 5, 10, 20, 25, 50, 100, 200 chosen to give that many), from the lowest point rounded down to the highest rounded up; if all points are equal the axis spans that value plus and minus one step.
- **Hover.** Over a point: the tooltip shows "<Name>: <level>" and "about N fps if only this setting changes", plus "(now)", "(recommended)" or "(this reading looks off)".
- **Sentences** under the graph, at most two: the largest steps between neighbouring points that cost 1 fps or more, in level order: "Medium to High costs about 10 fps." If no step costs 1 fps, the single sentence "This setting made no measurable difference here."
- **Readings that look off.** A level that measured faster than the nearest lower measured level by more than 3% of today's frame time (`deltaMs[i] < deltaMs[j] - 0.03 * nowMs`, j the nearest lower counted level) marks both levels as doubtful: both are drawn hollow, and a last sentence reads "Some readings look off; run the test again to confirm." The recommendation rules are unchanged; only the picture says it.
- **Crowd results** use the same graph on the crowd numbers (`recommend.crowdEntry`).
- **Results saved before this version** (menu green check) open in the same window: the graph reads only `deltaMs`, `value`, `current` and `cvar`, which every stored row has; flags and hitch counts are optional.

The graph is drawn with the client's line object when it has one (`CreateLine`), else with a row of small squares between the points; points are small buttons so they can show tooltips.

## 4. Rules and data

1. `Recommend.chartModel` (pure) gains `model.graphs` (the order of 3.4) with, per setting: `cvar`, `name`, `changed`, `swing`, `points = {{value, text, fps, current, recommended, doubtful}}`, `steps = {sentence}`, `notice` (the "no difference" or "look off" sentence parts), `unmeasured` entries with `reason`; and `model.axis = {min, max, ticks}`. Each change line carries `fpsSaved` and its text. The per-setting millisecond bars (`model.settings[].bars`) and `signed()` are removed; the pinned tests of those are rewritten and listed in the ledger.
2. `Results.lua` is rebuilt without the scroll frame; the drawing of one graph moves to a new file `Graph.lua` (pure drawing: takes a parent frame, a rectangle, a graph entry and the axis; returns nothing the caller needs). TOC order: `ForeverSettings, Names, Bench, Profiles, Recommend, UI, Settings, Graph, Guide, Results`.
3. `bench.run(onDone, opts)`, `bench.crowd(quiet, onDone, opts)` and `bench.verify(values, onDone, opts)` accept `opts.silent`; the guided window passes it. Only the lines of 3.1 stay when silent. `bench.check` is not changed (it is an Advanced command).
4. `profiles.adopt(name, values, silent)` and `profiles.switch(name, silent)` pass the flag on; nothing else about them changes.
5. The Save click: the refusal facts (`refusal()` in Results.lua) are unchanged; on success it sets a `saved` field on the open result so the window redraws with the green line and without the Save button.
6. Version 0.8.0.

## 5. Tests and how each is verified

Pure parts are written test-first, each rule with a mutant in `test/run.js` and a row in `test/run_mutations.sh`: the fps arithmetic and rounding, point order, the shared axis and its tick steps, the doubtful rule at its boundary, the step sentences (largest two, in order, the no-difference sentence), list order and default selection, the change lines in fps, the verdict sentences, `silent` on the three bench routines (what stays, what goes), `adopt`/`switch` with `silent`, and the older-entry case. The window is tested through the harness stubs: which buttons show for each status and what they say, the Save paths (change, nothing to change, refusals, double click), the green line, a list click redrawing the graph, the selection kept across a refresh, no `ScrollFrame` created, size 760 by 540.

**No harness for:** how the client draws lines, points, tooltips and the layout at the new size, and whether `CreateLine` exists in the Forever client. These are verified only in the game by the owner's walkthrough and screenshots. The ledger names this and offers the cost of a visual harness (a real client is the only faithful one) rather than adding one.

## 6. Review focus (failure modes the tests above must pin)

1. A result saved before this version (old labels, no flags, no `hitches`, no `quietTime`, a crowd entry) opens with graphs and no error, from the menu check and after a test.
2. A Save that is refused (combat, a running test, Original) leaves the profile untouched, shows the reason in the window and no chat line; a second click after success does nothing.
3. No steady reading, target out of reach, an invalid entry: no Save button, an empty or short list and no crash with zero graphs.
4. A setting with one measured point, only uncounted points, or all points equal: a graph or a "not measured" reason, never an error or a division by zero.
5. A guided test that stops, fails or is refused prints none of the removed lines, while the restore messages and the vsync and frame-rate-limit warnings still reach the player in the new words.

## 7. Release

0.8.0, one new file (`Graph.lua`), so the game needs a full restart. Install as before (backup `pre-results`, `_forever_` and the retail copy). Owner's walkthrough: run both tests and read the window; click through the settings list; hover points; save with a change and with nothing to change; reopen from the green check; check the odd Ground clutter reading; screenshots of every state; report how the lines and points look.

## 8. Out of scope

The max-everything button and the cost-versus-benefit view (W3), the restyle (W4), changes to measuring or to the recommendation rules, a "benefit" axis (how much better a level looks is the player's judgment, so the graphs show only cost), per-level costs in the My settings window, and removing the raw report from Advanced.
