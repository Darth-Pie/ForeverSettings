# The flat hub window (My settings rebuilt): design

Date: 2026-11-02. Status: the design was approved by the owner in chat (accent A, blue-violet); this written spec awaits review.
Builds on `2026-10-30-words-and-menu-design.md` (My settings, the plain words), `2026-10-30-maximum-and-costs-design.md`
(costs and totals) and `2026-11-02-picture-sharpness-slider-design.md` (the session-only slider).

## 1. What the owner asked

A wider My settings window with two or three columns of smaller buttons, skinned flat (no blocky outer frame), every option
on one screen with no scrolling, and a list of pages on the left where each page is its own small screen, organised
intuitively. The references are the owner's own example (a flat dark window with a page list on the left) and the options
panels of Leatrix Plus and Leatrix Maps: a near-black flat panel, a one-pixel border, a tiny close button, a gold title with a
small version line, a plain text list of pages with the current one as a filled bar, options in two columns under headings,
thin sliders, and a search box. The owner chose the blue-violet accent over gold.

## 2. What exists today

`Settings.lua` is one window (580 by 620, stock frame) with Everyday and Crowded tabs and one scrolling list of every
setting. Its data half, `settings.model`, is pure and well tested (levels, costs, matters, totals, the live line, the slider
block); its frame half is the part that changes. The minimap menu (profiles, tests, advanced) is unchanged by this work. The
guided test (`Guide.lua`) and the results window (`Results.lua`) are separate stock-style windows.

## 3. Decisions

| # | Decision | Why | Cost if wrong |
|---|---|---|---|
| H1 | One window, 780 by 560, named `ForeverSettingsSettings` as now: a header, a page list on the left (150 wide), a page area, and a footer strip on the pages that edit settings. | Wide enough for two columns of cards; tall enough that the fullest page needs no scroll. | A small screen may find it large; scale control is out of scope. |
| H2 | No stock frame. The window, its buttons, boxes and slider are drawn from flat colour textures: a 96% opaque near-black fill, a one-pixel border, a small close button. | The owner wants it flat; textures behave the same in every client, unlike backdrops. | None. |
| H3 | Palette A: fill `14161b`, border `3a3f4b`, divider `262a33`, control border `2f3440`, selected fill `232850`, accent `9a9cff`, accent light `c9caff`, text `d8dbe3`, bright `eef0f6`, dim `8b90a0`, warning `ff9933`, danger `e06060`. | The owner chose A. | A later palette change is one table. |
| H4 | The data half of `Settings.lua` stays as it is and gains `pages`; the frame half is rebuilt on a new shared `Skin.lua`. | The costs, totals and slider logic are proven; only the layout was the problem. Guide and Results can reuse the skin later. | The layout tests are rewritten. |
| H5 | Pages: Home, Light and shadows, World detail, Picture size, Tests and results, About. A setting appears on exactly one page by this table: Light and shadows holds `graphicsShadowQuality`, `graphicsSSAO`, `graphicsComputeEffects`, `giQuality`, `graphicsLightMode`; World detail holds `graphicsGroundClutter`, `groundEffectDensity`, `graphicsLiquidDetail`, `graphicsTextureResolution` and any setting the table does not know; Picture size holds `RenderScale`. | Themes a player can name, four or fewer settings a page. | A new setting lands on World detail until it is placed. |
| H6 | Each setting is a compact card: a tick that keeps it, its plain name, a one-line help, "matters" in words, small level buttons (36 by 22) with the cost under each. "(lowest)" and "(highest)" move to the button's tooltip. | The owner asked for smaller buttons and columns. | None. |
| H7 | Pages with settings are two columns of cards. A page with more than six cards uses three columns. | Keeps every page on one screen. | None. |
| H11 | Every button label is centred horizontally and vertically in its button, a label that wraps stays centred, and each button is sized so its standard label fits on one line (footer buttons 230 and 160 wide, 26 tall; level buttons 36 by 22; page and profile cards centre their title and note). The cost under a level button is centred under it. | The owner's review of the mockup: the footer labels wrapped and sat off-centre. | None. |
| H8 | Everyday and Crowded become a switch in the header of the pages that edit settings (Light and shadows, World detail, Picture size). | It replaces the tabs and costs one row less. | None. |
| H9 | Stage 1 (this spec) covers the window and the six pages. The Tests and results page opens the existing guided test and results windows. Restyling those two and folding them in as pages is Stage 2, its own spec. | Keeps the first change reviewable. | The three windows look different for a while. |
| H12 | The page list ends with two buttons, Save as Everyday over Save as Crowded (126 by 28, at the bottom of the list on every page), under the line "Save the game's current settings as:". A click keeps the game's current settings in that profile (the same save as the footer button, silently), and the line is replaced by "Saved N settings as Everyday." until the next click or redraw. Greyed in combat and during a test. A boosted picture sharpness is saved as it was before the boost. | The owner's request: a very clear save for each profile, reachable from any page. | Saving while Maximum is in use saves Maximum's levels; the footer button does the same. |
| H13 | The window is rounded by 8 pixels, and buttons, cards, tick boxes and the selected page row by 4. A rounded box is three colour strips plus four corner pictures for the fill, and four lines plus four ring pictures for the one-pixel edge, so it keeps the palette colours and the button states. The pictures are four small white TGA files in the addon's `Media` folder (`fill4`, `ring4`, `fill8`, `ring8`, each the top-left corner at twice its drawn size, flipped by texture coordinates for the other corners), made by `tools/make-corners.js` and checked by `tests/check_media.js`. The accent bar of a page row is inset 5 pixels top and bottom to stay clear of the corners. The slider stays square. | The owner's request: smoother, more pleasing corners. | If the pictures fail to load in a client, the corners show as white squares: the Media folder must be installed with the code. |
| H10 | Out of scope: a search box, a saved window position, a scale control, a Reload button, the minimap menu. | None of them is needed for the owner's request. | None. |

## 4. The window

Geometry (pixels at scale 1): header 36; page list 150 wide; footer strip 44; page area 614 wide with 16 of padding; two
columns of cards 298 wide with 18 between (three columns of 192 above six cards); a card is about 94 tall (name 16, help up to 2
lines of 13, 6 of gap, level row 22, cost 14, 10 below). A page area is 456 tall: a summary block of 44 at its foot (settings
pages), a page title (24), a notice banner (up to 30) and three rows of cards (282) fill 380 of the remaining 412. The fullest
page by the table in H5 has three rows.

Header: the title "ForeverSettings" in the accent colour, "Version x.y.z" small beside it, the close button at the right. The
window drags by its header and closes with Escape.

Page list: each page is a text row; the current one is a filled bar (selected fill, accent edge). A gap separates the four
settings pages from Tests and results and About.

Summary block (pages that edit settings): the lines the window shows today, "Your Everyday settings: about N fps ..." (with the
not-counted sentence when it applies) and "Everything at the highest: about N fps.", across the page area's full width at its
foot, up to three lines.

Footer strip (pages that edit settings): Use what I have in the game now and Switch to Maximum, right-aligned, with the same rules as today
(greyed when locked; Switch to Maximum absent while Maximum is in use). The footer holds nothing else.

Notices: the Original and Maximum notes, the lock reason and a refusal show as one banner at the top of the page area, in the
warning colour, as today's text does.

## 5. The pages

- **Home.** "In use now: Everyday" and four profile cards (Original, Everyday, Crowded, Maximum) with their one-line notes;
  Maximum shows "(about N fps)" when the test measured it. A click switches profile with the same rules and refusals as the menu.
  Below them: Find my best settings and Find my crowded settings (greyed while a test runs, ticked when a result is saved) and the
  line naming the test the costs come from.
- **Light and shadows, World detail.** The cards of H5/H6 for that page's settings. A setting the client lacks is left out; if a
  page ends up empty it says so in one line.
- **Picture size.** The Picture sharpness card, the slider block of the slider spec (label, slider, Back to normal, note, warning
  above 100%), and a status line for dynamic render scale: "Dynamic render scale is off." or "Dynamic render scale is on. It changes
  the picture size by itself, which spoils a test. Turn it off in the game's graphics menu." The line is absent in a client without
  the setting (CVar `dynamicRenderScale`, which Forever has).
- **Tests and results.** Find my best settings and Find my crowded settings; for each saved result, its zone and age and a Show
  results button; the progress line while a test runs. They open the existing windows.
- **About.** The version, one paragraph on what the addon does, the chat commands (`/fset settings`, `/fset profile`, `/fset size`,
  `/fset probe`, `/fset reset`), "It doesn't collect or send anything.", and where to report a problem.

## 6. State and model

`state = {tab = "everyday" | "crowded", page = "home" | "light" | "world" | "size" | "tests" | "about", notice}`. `settings.open(page)`
shows the window on that page (the page last shown when none is given, Home the first time); a call with `everyday` or `crowded`
selects that tab and the first settings page, so today's callers keep working. `settings.model(st, ctx)` keeps every field it has
and gains `view.pages` (key, text, selected) and `view.page` (the key); each row gains `page`. Clicks gain `page:<key>` and
`profile:<name>`; `tab:`, `keep:`, `level:`, `use`, `maximum`, `size:`, `sizeback` and `close` are unchanged.

## 7. The skin

`Skin.lua` loads before `Settings.lua`. It holds the palette (`skin.color(name)` answers r, g, b, a) and the frame builders:
`skin.window` (fill, one-pixel border from four thin textures, header, close button, drag, Escape), `skin.button` (states: normal,
hover, pressed, selected, disabled), `skin.check`, `skin.slider` (a bare slider whose thumb and track are flat textures),
`skin.text` (a font string in a palette colour) and `skin.divider`. A builder that cannot use a template falls back to plain frames.

## 8. Files

New: `Skin.lua`. Changed: `Settings.lua` (the frame half and `pages`), `Bench.lua` and `Guide.lua` (the dynamic render scale
warning, below), `ForeverSettings.toc` (`Skin.lua` before `Settings.lua`), the harness (loads `Skin.lua`; a test can read a
texture's colour and a button's state), `run.js` (`Skin.lua` among the mutation sources) and the format checks.

Dynamic render scale: the test's preflight warns when `dynamicRenderScale` exists and is not 0, in plain words, as it does for
vsync and the frame-rate limit, and the guided window explains it. The checklist line already tells the player to turn it off.

## 9. Tests and checks

- Model: pages and their order; each setting on exactly one page by H5; an unknown setting on World detail; the selected page; `open`
  with a page and with a tab; the Home profile cards with their notes, the Maximum figure and the refusals; the dynamic render scale
  status line in both states and absent.
- Skin: the palette values; a window's size, border and close button; a button's states by colour; a slider's range and flat thumb.
- Layout, through the harness: every page fits inside the page area with a worst-case text wrap (nothing scrolls; no scroll frame
  exists); two columns, or three above six cards; every button label centred both ways (centred anchor, centred justification, middle
  alignment) and on one line at its standard width; cards do not overlap; the footer strip stays under the page area; the page list
  marks the current page; a click on a page changes it; Escape closes the window once; no raw setting name in any text.
- Behaviour kept: every existing model test (costs, totals, the live line, Maximum, the slider block) passes unchanged except
  where a field moved; the layout tests of the old window are replaced.
- Mutation table: a row for each new rule. Full suites and the whole table pass before anything is installed.

## 10. What cannot be checked here

How the flat window looks and feels in the real client (colours, text sizes, hover states, the slider's thumb), and the tooltips.
The owner looks in game and sends a screenshot of each page; spacing then adjusts in small steps.

## 11. Stage 2 (a later spec)

Restyle the guided test and the results window with `Skin.lua`, and fold them into the hub as the Tests and results page's own
screens. The minimap menu stays a menu.
