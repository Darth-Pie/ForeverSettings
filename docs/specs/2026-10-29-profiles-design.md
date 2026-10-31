# ForeverSettings: profiles and undo (piece A of the novice mode), design

Status: draft written 2026-10-29 for the owner's review. Not approved. No implementation has started.
Builds on: `2026-10-28-forever-bench-design.md` (the benchmark, the restore, the minimap menu; sections 8, 10 and 15) and ForeverSettings 0.2.x as installed on 2026-10-29.

## 1. Intent

The owner wants ForeverSettings to be usable by friends who know nothing about graphics settings: install it, answer a few questions, get sensible settings for everyday play and for crowded play (raids, large dungeons, battlegrounds, busy cities), switch between them when they choose, and undo in one click without risk to their game.

That is three fairly separate pieces, agreed with the owner on 2026-10-29 and to be designed, built and tested in the game in this order:

- **A. Profiles and undo** (this spec): named setting sets, manual switching, one-click return to the player's own settings.
- **B. Guided tests and recommender** (later spec): two guided benchmarks per player, one in an empty area and one in a crowded area, and a recommendation for each profile. The crowded test needs a noise limit looser than the current 5%, to be calibrated in a real crowd.
- **C. Novice window** (later spec): one plain-language window that drives A and B.

Decisions already made by the owner for A:

- Two profiles with fixed names, **Everyday** and **Crowded** (the names were chosen during design).
- **Manual switching only.** No switching on zone, instance, group size or frame rate. The addon never changes a setting except in answer to a click, a typed command, a key press, or the loading-screen re-apply of the profile the player chose.
- The Crowded profile may also set the game's own raid and battleground graphics set, as an option the player decides (section 6).
- Switching is by minimap menu, slash command and a keybinding (the owner chose all three).

Success for A: a player can save two profiles, switch between them in a few clicks or one key, see which is active, and return to their own settings with one click, and every switch is verified by reading the live settings back.

Not in A: guided tests, recommendations, the novice window, automatic switching of any kind, more than two named profiles, importing or exporting profiles.

## 2. Facts this design rests on

- Both installed clients already have a complete raid graphics set in `Config.wtf`, and it differs from the normal set (retail: `raidGraphicsShadowQuality` 3, `RAIDgroundEffectDensity` 80; Forever: 4 and 48). The game uses its raid set by itself in raid groups and battlegrounds. The 0.1 addon forced only the normal `groundEffectDensity`, so in a Forever raid the game would have used its own 48.
- Neither `Config.wtf` contains a setting that switches the raid set on or off (searched for `RAIDsettingsEnabled`; no match). This is unconfirmed, see section 10.
- Retail has no `giQuality` and no `graphicsLightMode` (the benchmark's lighting row is skipped there); Forever has both.
- Tested in the owner's retail game on 2026-10-29: forced settings are re-applied at the loading screen after a reload; the minimap menu ticks follow the live setting; the restore puts every guarded setting back after a stop, a movement stop, a reload and an alt-tab during a run; the final config comparison showed no graphics setting changed.
- Policy reading (Blizzard UI Add-On Development Policy, 2009, no later revision shown): no rule addresses graphics settings, automation or frame timing; rules 2, 3, 7 and 8 touch the addon. The current Terms of Use and EULA, and any rules specific to Forever, were not read. Manual switching keeps the addon to what the player could do by hand in the Graphics menu.

## 3. What a profile is

A profile is a named set of values for the settings the benchmark measures (the "managed settings"): `graphicsShadowQuality`, `graphicsSSAO`, `graphicsComputeEffects`, `giQuality`, `graphicsLightMode`, `graphicsLiquidDetail`, `graphicsTextureResolution`, `graphicsGroundClutter`, `groundEffectDensity`, `RenderScale`. It holds none of the roughly 100 raw settings the game derives from the menu-level ones; the game rewrites those itself when a menu-level setting is written.

There are three profiles:

- **Original**: the player's own values, captured by the addon (section 4, step 2). Hands-off: while it is active the addon enforces nothing. It cannot be edited.
- **Everyday** and **Crowded**: saved by the player with "Save current settings as ..." (section 5). Until saved, each holds no values; switching to it restores the Original values, enforces nothing, and says so ("Crowded has no saved settings yet: set things up in the game menu, then Save current settings as Crowded").

A managed setting that does not exist in the running client (for example `giQuality` on retail) is skipped: it is neither captured, written, nor reported as an error. An absent setting is never read as "removed" or "turned off". The same rule covers a profile that lacks a value, a client that lacks the setting, and a failed lookup.

## 4. Switching and undo

Choosing a profile, by menu, `/fset profile <name>` or the key, does this in order:

1. **Refuse** with a plain message when in combat, or while a benchmark is busy: a check, a run or a mark (`bench.active()`), or `ns.suspended`. A `mark` window sets the first and not the second, so both are tested.
2. **Capture Original.** If the active profile is Original and the target is not, capture the live value of every managed setting and of its raid counterpart (section 6) that exists in the client, replacing the stored Original. A switch between Everyday and Crowded leaves Original as it is.
3. **Plan.** The target values are: for Original, the captured Original values; for Everyday or Crowded, for each captured name the profile's value if it has one, else the Original value; plus any extra settings the profile holds. If the target is Crowded and the raid option is on, each raid counterpart gets the value of its normal setting. Otherwise raid counterparts get their Original values.
4. **Write** each target value whose live value differs *at the moment of its own write*, in the order the restore already uses (master presets first, then menu-level settings, then raw), each write inside `pcall`; then make the same pass once more. A write can make the game rewrite another setting (a menu-level write moves the raw setting derived from it), so "differs" cannot be decided before the first write. (Clarified after the whole-result review, finding F1.)
5. **Read back** every planned value, not only the written ones, and report in plain words any the game refused or changed ("Shadows stayed at 4 (wanted 1)"). The read-back is the gate: a switch is reported as done only for settings whose live value matches, and "settings changed" counts those that now match and did not before.
6. **Enforce.** The enforced list (`db.want`, re-applied at every loading screen by the existing, tested code) becomes the profile's own values plus, for Crowded with the raid option on, the mirrored raid values. It is empty for Original. Values that only return to Original (step 3) are written once, never enforced. When the loading-screen re-apply has to put a setting back, it says so in chat.
7. **Say** "Profile: Crowded" with the number of settings changed. The active name is saved. When the profile switched to is Everyday or Crowded, is not empty, and would write exactly the same settings as the other one just left (compared as planned: Original plus each profile's own values, with the raid mirror when it applies), also say so: "Crowded holds the same settings as Everyday right now: to make them differ, switch to one of them first, then change a setting (/fset set or the Tiers menu)". Original never gets this line, and neither does a switch to the profile that is already active. (Added at the owner's request after their first in-game session, where `/fset set` on Everyday followed by "save as Crowded" left two identical profiles and every switch said only "nothing needed changing".)

**Undo** is choosing Original: it writes the captured values back, reads them back, and enforces nothing. There is no separate undo to learn. This replaces `/fset reset`, which restored the first value the addon ever saw and put the owner's Shadows to the wrong value.

## 5. Controls

Every control calls the same function as its slash command; the menu and the key hold no logic.

| Command | Does |
|---|---|
| `/fset profile` | Shows the active profile, the raid option, and for each saved profile how many settings it holds. |
| `/fset profile original`, `everyday`, `crowded` | Switches (section 4). |
| `/fset profile save everyday`, `crowded` | Captures the live values of the managed settings that exist into that profile, replacing those values and keeping any extras. Allowed in combat (it only reads); refused for Original and during a benchmark. If that profile is active, the enforced list follows. |
| `/fset profile raid on`, `off` | Sets the raid option; if Crowded is active it is applied again. If applying would be refused (combat, benchmark busy), the option is left as it was and the reason is said. |
| `/fset profile toggle` | Crowded to Everyday; from anything else to Crowded. |
| `/fset reset` | Same as `/fset profile original`. |

**Minimap menu.** A "Profile" section directly under the title: three ticked items (Original (hands off), Everyday, Crowded) whose ticks read the live state, a "Save current settings as ..." submenu (Everyday, Crowded), and the checkbox "Crowded also sets the game's raid and battleground graphics". The profile items and the raid checkbox are disabled in combat and during a benchmark; the save buttons only during a benchmark. The forced-settings section and the tier submenus stay (section 7).

**Keybinding.** A `Bindings.xml` adds "Toggle Everyday / Crowded" to the game's Key Bindings screen, unbound until the player picks a key; it runs `/fset profile toggle`. The binding's label is defined in Lua (`BINDING_NAME_FOREVERSETTINGS_TOGGLE`); its group is the file's `category="ForeverSettings"`, which gives it its own "ForeverSettings" section as the addons installed beside this one (Plumber, Porter, EnhanceQoL) do. (First written with `header=`; in the owner's game the newer Key Bindings screen showed that as a raw "HEADER_FOREVERSETTINGS" row under "Other". `run_all.sh` now requires `category="ForeverSettings"` and forbids `header=`.)

**Tooltip.** The minimap button's tooltip adds "Profile: Crowded".

## 6. The game's raid set

The option "Crowded also sets the game's raid and battleground graphics" is off by default and can be changed at any time (menu or `/fset profile raid`). When on, applying Crowded also writes these raid counterparts, from a fixed table:

| Normal setting | Raid counterpart |
|---|---|
| `graphicsShadowQuality` | `raidGraphicsShadowQuality` |
| `graphicsSSAO` | `raidGraphicsSSAO` |
| `graphicsComputeEffects` | `raidGraphicsComputeEffects` |
| `graphicsLiquidDetail` | `raidGraphicsLiquidDetail` |
| `graphicsTextureResolution` | `raidGraphicsTextureResolution` |
| `graphicsGroundClutter` | `raidGraphicsGroundClutter` |
| `groundEffectDensity` | `RAIDgroundEffectDensity` |
| `giQuality` | `RAIDgiQuality` |
| `graphicsLightMode` | `raidGraphicsLightMode` |
| `RenderScale` | none (neither config has one) |

All of these names are in the built-in CVar list. When the option is off, or when the player switches to Everyday or Original, the raid counterparts go back to the values Original captured, so Crowded never leaves the raid set changed after the player leaves it. The addon switches nothing when the player enters a raid: the game does that itself.

## 7. Storage, migration, and today's forced list

Saved in `ForeverSettingsDB`: `profiles` (`everyday` and `crowded`, each `{values = {cvar = value}}`), `active` (`original`, `everyday` or `crowded`), `original` (`{values = {...}}`), `raidToo` (boolean). The enforced list `db.want` is derived from the active profile (section 4, step 6); the loading-screen code that applies it is unchanged.

- **Tiers menu, `/fset set` and `/fset unset`** now edit the active profile: a tier click or `/fset set <cvar> <value>` changes that value in the profile, saves it and applies it. With Original active they are refused with "pick Everyday or Crowded first". A profile may hold extra settings added with `/fset set` (any CVar the client knows); they stay until `unset`, and "Save current settings" does not touch them. When an extra is first added, its live value is recorded in Original, so that choosing Original puts it back; `unset` leaves the live value as it is, as today.
- **`db.orig` and `/fset reset`.** `db.orig` is dropped. `/fset reset` becomes `/fset profile original`.
- **First run of this version, migration.** If `db.want` has entries (from the 0.1 defaults, `/fset set`, or tier clicks), they become Everyday's values, Everyday becomes active, and Original is the live values of the managed settings except that, for each name that was in `db.want`, `db.orig` supplies the value when it has one. Entries in `db.orig` for names not in `db.want` are discarded. If `db.want` is empty, the player starts on Original with Everyday and Crowded empty. The Forever copy therefore keeps forcing `groundEffectDensity = 64` through Everyday, and the friends' package (empty defaults) forces nothing.
- **Benchmark.** Each saved run and each `mark` records the profile that was active (`entry.profile`), which prepares piece B. The benchmark still suspends enforcement and restores everything, as in the benchmark spec; the profile controls are locked while it runs.

## 8. Files

- New `Profiles.lua` (loaded after `Bench.lua` and before `UI.lua`): the managed-settings and raid tables, capture, plan, switch, save, migration, the command routing for `profile`, and the binding names.
- New `Bindings.xml` (loaded by the game from the addon folder).
- Changed: `ForeverSettings.lua` (routes `profile` and `reset`; `set`/`unset` edit the active profile; first-run migration), `UI.lua` (the Profile section, the tooltip line), `Bench.lua` (one field, `entry.profile`), `ForeverSettings.toc` (one line for `Profiles.lua`, version), and the test harness and runner (one more source file).

## 9. Testing

Written test-first against the simulated game, each rule with a mutation check, in a new `test_profiles.lua` plus additions to the existing suites:

- The mapping tables: every managed name and raid counterpart is in the built-in list, and the table matches section 6.
- Capture: only existing settings; none invented; Original replaced only when leaving Original.
- The plan: Everyday and Crowded cases, a missing profile value falls back to Original, extras kept, raid option on and off, raid values returning to Original on leaving Crowded.
- Switching: refused in combat and during a benchmark; read-back reports a refused value and a clamped value; a game that rewrites derived values; the write order; the enforced list contents (own values only, not the return-to-Original values).
- Undo (Original): values restored and verified by a live read, enforcement emptied.
- Save: managed settings only, extras kept, refused for Original and during a benchmark.
- Migration: the 0.1 defaults, a stale `db.orig`, an empty list, a repeat run changing nothing.
- Commands and menu: each route reaches the right function; the Profile ticks read the live state; the items are disabled in combat and during a run; the tooltip line; `reset` equals Original; the binding names exist.

Not testable outside the game, to be checked there: the keybinding file loads and runs; the menu layout; whether the raid values take effect (the final `config-snapshot.ps1 Diff` shows them written and restored); the raid on/off switch; Forever itself (opens 4 November 2026).

## 10. Unconfirmed, and what the player gets if it is false

| Unconfirmed | If false |
|---|---|
| The game has a separate on/off switch for its raid set | If it exists and is off, the raid values are written but ignored; the menu shows "the game's raid settings are switched off" and leaves that switch alone. If it does not exist, nothing changes. Checked with one command in the game before the plan is written. |
| The raid counterpart names exist in the running client | A name that does not exist is skipped and listed once in plain words; the rest of the profile applies. |
| `Bindings.xml` loads and its action runs | The menu and slash command still switch; the key is the only thing missing. |
| Forever has the same setting names (its lighting setting in particular) | Absent names are skipped with a message; the profile works for the others. Known only after 4 November. |
| The client writes `Config.wtf` and the saved variables at the same moments (logout, reload) | After a client crash the saved active name could disagree with the live settings; the next login re-applies the saved profile, so the settings catch up. |
| Raid values written in the middle of a session take effect at once rather than at the next raid entry | No effect on correctness; the config comparison shows what was written. |

## 11. Out of scope

Guided tests, the recommender and the noise-tolerant crowded test (B); the novice window, plain-language explanations and the one-time setup questions (C); the friends' package (README, licence, changelog); automatic switching; custom profile names; import and export.
