# My settings edits the profile in use: design

Date: 2026-11-02. Status: approved by the owner in chat (the owner found the Everyday/Crowded tabs and the footer buttons "really
confusing" and asked for a strong visual simplification plus a coloured dot showing the profile in use; the owner chose: one rule as
mocked up, the dot in a header pill by the close button, the colours as shown).
Replaces in `2026-11-02-flat-hub-window-design.md`: H8 (the Everyday/Crowded switch on the settings pages) and the footer of H6; and
S13 of `2026-11-02-one-saved-picture-size-design.md` (the where line and Switch to <tab>).

## Decisions

| # | Decision | Why |
|---|---|---|
| P1 | One rule: the settings pages edit the profile in use. A level click, a tick, the slider and Back to 100% change that profile and the game at once. There are no Everyday/Crowded tabs any more. | "Stored but not applied" was the source of the 100% report and of most of the confusion. |
| P2 | Original and Maximum cannot be edited. With either in use the settings pages show the game's levels greyed (ticks greyed and set for what that profile holds), and one line under the page title says "Maximum can't be changed. To change settings, edit:" followed by two buttons, Everyday and Crowded (each with its dot), that switch to that profile. | A clear way out instead of a dead page. |
| P3 | The footer goes: "Use what I have in the game now" duplicated Save as, and Switch to Maximum is on the Home page. The summary block moves down into that space. | Fewer buttons, more room. |
| P4 | A profile pill in the header, left of the close button: a coloured dot and the name of the profile in use, on every page. Clicking it opens the Home page. The four Home cards show the same dot. | The owner's request: always see which profile is on. |
| P5 | Colours: Original grey `b4b2a9`, Everyday teal-green `5dcaa5`, Crowded amber `ef9f27`, Maximum coral `f0997b` (palette names `profileOriginal`, `profileEveryday`, `profileCrowded`, `profileMaximum`). A dot is a circle of 8 pixels drawn with the rounded box of radius 4. | Distinct from each other and from the violet accent, readable on the dark window. |
| P6 | Save as Everyday and Save as Crowded stay as they are, at the bottom of the page list, and keep saying what they replaced. | The owner asked for them; they copy the game's settings into a profile, which is still useful (from Maximum, or after changing the game's own menu). |
| P7 | The picture size block follows P1: its label is "Picture sharpness right now: N%", its note says whether the profile in use keeps the size; with Original or Maximum in use the slider and Back to 100% are greyed and the note is left out. | The where line of S13 has nothing left to say. |
| P8 | The "Your <profile> settings: about N fps" line is for the profile in use; with Original or Maximum in use it is left out (Maximum has its own "Everything at the highest" line). | One profile, one estimate. |

## Out of scope

The minimap menu (its ticks already show the profile in use), the results and guide windows (the 1.0 restyle).
