# Picture sharpness slider (this session only): design

Date: 2026-11-02. Status: approved by the owner in chat (the plan of 2026-11-02, then "go ahead", then "once that's done install it").
Builds on `2026-10-30-words-and-menu-design.md` (the My settings window) and `2026-10-29-profiles-design.md` (profiles and
enforcement).

## 1. What the owner asked

"A slider on My settings that lets you render the game up to 200%." The game's Render scale (the CVar `RenderScale`; the addon
calls it Picture sharpness) goes above 100% in the game's own menu, which draws more pixels than the screen has.

## 2. The hazard that shapes the design

The addon keeps the levels of a profile and applies them again at every loading screen, login included. Saved variables are
written only when the game exits normally, so a crash cannot leave a warning behind for the next login to read. A value above
100% saved in a profile would be applied at every login; on a PC whose driver crashes at that size (the owner has seen an AMD
driver crash with ray traced shadows) the game would crash at every login. So a value above 100% is never saved.

## 3. Decisions

| # | Decision | Why | Cost if wrong |
|---|---|---|---|
| R1 | The slider changes the live game only. Nothing goes into a profile or into the saved list. At logout the value from before is put back. | A crash then leaves the game's own saved value untouched (the game writes its settings only on a normal exit), so no crash can repeat. | A player who wants 150% every day has to set it each session. A later "keep this size" step can add saving, with its own safeguards. |
| R2 | It is its own block of the window ("Picture sharpness right now"), not tied to a tab. | A tab is a stored profile; this is the game right now. | None. |
| R3 | The value is applied when the mouse button is released, not while dragging. | Every step of a drag would rebuild the game's render targets. | None. |
| R4 | Range 50% to 200%, steps of 5%. Below 100% it is also this-session only; the level buttons are the saved route. | One rule is easier to explain than two. | None. |
| R5 | The change ends (the value from before goes back) on Back to normal, on `/fset size off`, at logout or reload, and when a test starts. A level click for the same setting takes over instead, and so does any profile switch (a switch writes every managed setting, Original's value for those the profile does not hold). | A test must measure the normal size; a profile or a level the player chose must win over a boost. | A reload also ends a boost. |
| R6 | While the game holds the boosted value, enforcement at loading screens leaves that setting alone. Once the game holds anything else, the boost is over. | Otherwise the next loading screen would undo it. | None. |
| R7 | No frame rate is promised above 100%: the test measured nothing there, so the "Your settings" total counts the setting as "not counted". | Honesty about what was measured. | None. |
| R8 | `/fset size 50` to `/fset size 200`, and `/fset size off`, do the same from chat. | At 2 frames a second a slider is hard to drag; chat is not. | None. |

## 4. Behaviour

- The block shows: a label "Picture sharpness right now: N%", the slider, a Back to normal button (enabled only while a boost is
  active), a note "Not saved: the game goes back to your normal setting when you log out.", and above 100% a warning "Above 100%
  the game draws more pixels than your screen has. That can cost a lot of frame rate and graphics memory, and some graphics cards
  crash at high values."
- It is greyed in combat and during a test, with the window's usual reasons. Without a `RenderScale` setting in the client the
  block is absent.
- If the game keeps a different value than asked, the window says so in plain words and the boost records what the game holds.
- `/fset size` alone says the current size and whether it is a boost.

## 5. Where it lives

- `Profiles.lua`: the boost (`profiles.boost`, `profiles.unboost`, `profiles.boosted`), kept in memory only; `setValue` and `switch`
  end it when they write the same setting.
- `ForeverSettings.lua`: `applyAll` skips the boosted setting; a `PLAYER_LOGOUT` handler puts the value back; the `size` command.
- `Bench.lua`: every test begins by ending a boost (`beginRun`).
- `Settings.lua`: the block, its model (`view.size`) and the clicks `size:<percent>` and `sizeback`.
- The harness gets slider methods (`SetValue`, `GetValue`, `SetMinMaxValues`).

## 6. What cannot be checked here

How the slider looks and drags in the real client, and the revert at a real quit (the harness fires the event itself). The owner
tests both in game.

## 7. Out of scope

Saving a value above 100%; measuring above 100% in the test; raytracing or any other beyond-Ultra setting.
