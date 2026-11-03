# Tests and results as pages of My settings — design

Date: 2026-11-03. Status: for the owner's review. Target: 0.10.1, built tonight, so the Forever stress test of 2026-11-04 runs it.
Fallback: the build installed now (0.10.1 without this change) stays in the game folders until this one passes its tests and review;
if it is not ready, tomorrow's run uses that build.

## What the owner asked

1. The **Find your best settings** window (the guided test) and the **Your best settings** window (the results, with the graph) take
   the flat look of My settings and become **pages of My settings**, reached from the page list on the left.
2. The graph gets the same look.
3. **Clicking a point of a graph chooses that level** (the 1.0 idea, brought forward; the owner's answers of 2026-11-02 apply, in
   `docs/superpowers/ideas/2026-11-02-restyle-results-guide-clickable-graph.md`).

Decided with the owner (2026-11-03): pages built on the existing models; the two page names are **Find my settings** and **My
results**, replacing **Tests and results**; while a test runs the window stays on the test page; clickable points tonight.

## M1. Two pages replace Tests and results

The page list becomes: Home, Light and shadows, World detail, Picture size, (gap) **Find my settings**, **My results**, About.
`settings.open("test")` and `settings.open("results")` open them. Nothing else of My settings changes (the pill, the save bar, the
other pages).

## M2. Find my settings (the guided test as a page)

- What the page says and which buttons work comes from `guide.model` and the flow of Guide.lua, **unchanged** (intro, running,
  stopped, done; setup, crowd, check and run). Only the drawing moves: it is rebuilt from Skin.lua widgets inside the page area
  (title, text, the frame-rate target buttons and the Quick/Thorough pair as selectable skin buttons, the tick box as skin.check,
  the action buttons as skin buttons along the bottom of the page).
- With no test open, the page shows the two test buttons (Find my best settings, Find my crowded settings) and a line on what each
  does. They open the guide's intro for that test. Cancel and Close in the guide's views come back to these two buttons.
- Everything that opened the guided test window now opens this page: the Home buttons, the minimap menu (Find my best settings, Find
  my crowded settings, Advanced: Check this spot, Run benchmark), the slash commands. `guide.open(kind)` keeps its meaning.
- **While a test runs** the window stays on this page: the other page links, the pill and the save bar are greyed; the close button
  and Escape do nothing; Stop is the way out (as the old window: it came straight back if hidden). The "please don't move" banner
  and the progress show as today, refreshed every half second.
- Show report (the Advanced run) still opens the separate report window, as today.

## M3. My results (the results window as a page)

- What the page shows comes from `recommend.choose` and `recommend.chartModel`, **unchanged** in meaning: the verdict, the now /
  with-these-changes bars and the target mark, the list of changes, the checked line, where and when it was measured, the hint, the
  setting list with the graph of the selected setting, the footer, and the Save button ("Save these as my Everyday settings" /
  "Replace my ... settings with these"), Run it again.
- Laid out for the page area (about 678 by 520): verdict on top; bars on the left, changes on the right; the setting list (left) and
  the graph (right) below; notice, footer and buttons at the bottom. The separate Close button goes (the window has its X).
- A finished best or crowded test opens this page with its result. With no result open, the page lists the saved results (the
  quiet-spot test and the crowd test, as the Tests and results page did) with a Show results button each, and a line pointing to
  Find my settings when there is none. `ui.openSaved(kind)` opens a saved result here.
- The offer lasts while the window is open: switching to another page and back keeps it; closing the window ends it (as closing
  the results window did). Save is greyed in combat and during a test, with the reason, as today.

## M4. The graph's new look

Drawn in the window's palette: grid lines in the divider colour, axis numbers dim, the line in the accent colour, each point a small
round dot (the rounded-box pictures), the level in use ringed in bright, the recommended level in the accent colour with its tag,
a picked level (M5) in the colour of the profile it will be saved to (Everyday green, Crowded orange) with the tag "your pick".
The test colours of each element stay distinct and are read from one table, so the tests still tell the elements apart.

## M5. Clicking a point chooses that level (staged until Save)

- Each point is a button of at least 20 by 20 pixels. A click **stages** that level for that setting in the offer; nothing is
  written to a profile or the game until Save. Clicking the recommended level (or, for a setting the recommendation leaves alone,
  the level in use) removes the pick.
- A new pure function, `recommend.withPicks(result, picks)` ({cvar = level}), gives the result with those levels chosen: the
  changes, the unchanged list, the estimated frame time and fps (the same sum `choose` uses, never past the speed-up cap), and the
  status (change when any level differs from the level in use, else nochange). `chartModel` draws it as today.
- After a pick: the verdict and the with-these-changes bar show the new **estimate**; the checked (measured) figure no longer
  applies, so the bar says "(estimate)" and the checked line becomes "Checked before your changes: ... Run the test again to
  measure your picks."; the setting list marks every picked setting ("your pick"); a **Back to the recommendation** button appears
  and clears all picks. Save saves the levels as shown (the recommendation with the picks).
- Only measured levels are points, so only they can be picked; settings not measured, the Advanced (console-only) settings and
  picture sizes above 100% are not on any graph.
- In combat and during a test the points do not react (read-only), as the other controls.
- The click goes through one function, so applying straight to the profile instead of staging can be tried later by changing it
  alone.

## M6. The three small changes (approved 2026-11-03)

- The gauge icon (Media/icon.tga) at 20 by 20 at the left of the title bar of My settings; the title and the version label move
  to its right.
- `## IconTexture: Interface/AddOns/ForeverSettings/Media/icon.tga` in the TOC, so the game's AddOns list shows the icon.
- The TOC Notes in plain words: "Finds good graphics settings for your PC and keeps them. An addon for WoW Forever."

## Testing

- The models and the flow keep their tests (test_guide's model and flow tests, test_results' model tests, test_recommend).
- New tests: `recommend.withPicks` (picks that change, undo, keep-as-now, unmeasured levels refused, the cap, status), the two pages
  (what each view draws, the chooser, the locked page while running, Escape and the close button while running, the finished test
  opening My results, Show results, the offer surviving a page switch and ending with the window), the graph's look and point
  buttons (size, colours, ring, tag, pick mark), clicks staging and Save saving the shown levels, read-only in combat.
- The drawing tests of the two old windows and of the Tests and results page are replaced by page tests; their mutation rows are
  re-anchored or replaced, and every new row is checked killed. Full suites, the format check, a fresh review of the diff and the
  full mutation table before install.

## Out of scope

Changing what the recommender chooses; measuring more levels; the report window; the restyle of the minimap menu; an Advanced page.
