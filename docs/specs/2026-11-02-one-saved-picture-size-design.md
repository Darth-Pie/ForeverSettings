# One saved picture size: design

Date: 2026-11-02. Status: approved by the owner in chat (the owner chose "same range and same saving", the buttons 125, 150, 175 and 200%,
the Shift safe start, and 0.10.0 first with this as 0.10.1).
Replaces the session-only rules of `2026-11-02-picture-sharpness-slider-design.md` (R1, R4, R5, R6 and R8 there). Builds on
`2026-11-02-flat-hub-window-design.md` (the Picture size page) and `2026-10-29-profiles-design.md` (profiles and enforcement).

## 1. What the owner asked

"Let's make the slider match the buttons and vice versa." Asked what that means, the owner chose: the slider saves any value like
a button does, and the buttons go up to 200% like the slider. So there is one setting with two controls.

## 2. The hazard, and how this design stays safe

A saved size above 100% is applied again at every loading screen. Worse, the game writes its own settings (Config.wtf) when it
exits normally, so a size above 100% that the game holds at exit would be loaded by the game itself at the next start, before any
addon runs, and "switch the addon off" would not help. On a PC whose driver crashes at that size the game would then crash at
every start. So:

- At logout, and at reload, a size above 100% that the addon is keeping is put back to 100% in the game's own settings first. The
  game's saved settings therefore always start at a safe size, and the addon applies the saved size after the player has entered
  the world.
- Holding Shift while entering the world skips any saved size above 100% for that session, so a size that crashes the game can
  always be got out of.

A crash leaves the game's saved settings as the last normal exit wrote them (at a safe size), so the game starts, and the addon's
Shift skip is then available.

## 3. Decisions

| # | Decision | Why | Cost if wrong |
|---|---|---|---|
| S1 | The slider and the level buttons set the same thing: the picture sharpness of the tab shown (Everyday or Crowded). Letting go of the slider at P% does what clicking a P% button does: it is saved in that profile, the card's tick is set, and it is applied at once when that profile is in use. | One setting, two controls. | None. |
| S2 | They always show the same value. The value is the tab's: the game's current size when the tab is the profile in use, else the size the tab keeps; a tab that keeps none highlights no button and the slider shows the game's current size. | "Match each other." | None. |
| S3 | The levels are 50, 60, 70, 80, 90 and 100% (the ones the test measures) and 125, 150, 175 and 200% (never measured: their cost shows "?"). The guided test, the recommender and Maximum use the measured levels only, so none of them ever picks more than 100%. | Honesty about what was measured; the test must not run at 200%. | None. |
| S4 | The slider keeps its range 50 to 200% and steps of 5%, applied when the mouse button is let go. | As before. | None. |
| S5 | The Picture size page is one full-width card, so the ten buttons share a line. | Ten buttons do not fit a half-width card on one line. | None. |
| S6 | "Back to normal" becomes "Back to 100%": it sets 100% like the 100% button. It is enabled when the tab's size is not 100%. | There is no session-only change to take back any more. | None. |
| S7 | The page keeps the warning above 100% and adds one line: "If a size above 100% crashes the game when you enter the world, hold Shift while you enter: the addon then skips it for that session." The line "Not saved ..." goes; a line says whether the size is kept in the tab's profile. | The way out has to be findable. | None. |
| S8 | Logout and reload: if the addon is keeping a RenderScale above 100% (the profile in use holds it) and the game holds one above 100%, RenderScale is set to 100% first. Nothing else is touched. | Section 2. | A player who changes the game's own menu size above 100% with nothing kept is left alone. |
| S9 | Safe start: if Shift is held at the first PLAYER_ENTERING_WORLD of a session (login or reload), enforcement skips any saved RenderScale above 100% for the rest of that session and says so once in chat. A change the player makes (a click, the slider, a profile switch, a command) still applies. | The escape from a crash. | None. |
| S10 | `/fset size 50` to `/fset size 200` does what `/fset set RenderScale <fraction>` does in the profile in use (refused on Original and Maximum, like every edit). `/fset size off`, `normal` and `back` set 100%. `/fset size` alone says the current size and whether the profile in use keeps one. | Same saving from chat. | None. |
| S11 | Removed: `profiles.boost`, `unboost`, `boosted` and `liveValue`, the boost step in `switch` and `setValue`, `Bench.releaseBoost`, the boost skip in `applyAll`, and the boost revert at logout (replaced by S8). | Nothing is session-only any more. | None. |
| S13 | A tab that is not the profile in use only stores what is chosen on it. The size block then says so under the slider ("The game is using Maximum. Changes here are stored in Everyday and take effect when you switch to Everyday."), the footer has a **Switch to Everyday** (or Crowded) button left of Use what I have in the game now, and Save as Everyday or Crowded and Use what I have in the game now say which settings they replaced ("Picture sharpness was 150%, now 100%", at most three, then "and N more"). | The owner's report: with Maximum in use the slider seemed to do nothing, then Save as Everyday copied the game's 100% over the stored 150%. | None: nothing underneath changes. |
| S12 | The window says what the game would not take: "The game kept picture sharpness at N% (you asked for M%)." when the tab is in use and the game holds another value after the change. | As before. | None. |

## 4. Where it lives

- `Profiles.lua`: the boost code is removed; `live` reads the game directly again.
- `Settings.lua`: the model builds the extra levels for RenderScale only, derives the slider value and label from the same value as
  the buttons, and has `size:<percent>` and `sizeback` save through `profiles.setProfileValue`; the Picture size page is one column.
- `ForeverSettings.lua`: `applyAll` skips a saved size above 100% in a safe-start session; the first PLAYER_ENTERING_WORLD reads
  Shift; PLAYER_LOGOUT does S8; `/fset size` as S10.
- `Bench.lua`: `releaseBoost` and its four calls are removed.
- Tests and mutants follow the code; the session-only tests (SZ, TS, S4 and the bench ones for the boost) are rewritten for the
  saved behaviour.

## 5. Out of scope

A delay before applying, a confirmation dialog above 100%, and detecting the graphics card.
