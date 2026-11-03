# The Advanced page, the title-bar switch and the new minimap menu — design

Date: 2026-11-03. Status: for the owner's review. Target: 0.11, after 0.10.1 is released (the release gate stays: the Forever check
on 2026-11-04). The settings table in A6 is a list of candidates until the owner's `/fset probe` results from retail and Forever
confirm which settings each client has.

## What the owner asked (2026-11-03)

1. Every graphics option, including the ones only a console command can change (the reddit macros: ground clutter 256, bloom and
   the rest), with the console-only ones on their own page, **Advanced**, which a title-bar option shows or hides.
2. A clear warning that the Advanced settings are finicky and for people who know what they are doing.
3. The title bar's profile pill becomes a quick switch between **Everyday** and **Crowded** (a rocker).
4. A rearranged minimap menu: the window's link first and more prominent, named **Settings**; the profiles by name only, their
   descriptions as hover hints; **Return to Original** in place of "Put back everything this addon changed"; the raid option and the
   advanced tools move to the Advanced page.

Decided with the owner (2026-11-03): game-menu settings the addon does not manage yet join the normal pages and are measured;
console-only settings go to Advanced, unmeasured; Advanced values are kept in the profile with a safety net for risky ones; the
rocker lights neither side on Original or Maximum; Advanced is off by default and must be accepted once; Return to Original;
Advanced uses level buttons, as the other pages.

## A1. More settings on the normal pages (measured)

- The game-menu graphics settings the addon does not manage yet (candidates in A6, part 1) join Light and shadows or World detail,
  as cards with a keep tick, their levels and the cost under each level, exactly as the settings there today.
- The test measures them as it measures the others, so they get costs and a graph on My results. The test gets longer; the intro's
  minutes come from the window count, as today.
- **Grass and plants (exact amount)** offers 256 as its highest level, beside 48, 64 and 128. The test measures what the client
  accepts; a client that refuses 256 does not show it (the game's answer to the set is the rule, as for every level today).
- A setting a client does not have is not shown on that client, as today.

## A2. The Advanced page

- A page **Advanced**, at the end of the page list (above About), shown only while Advanced is on (A3).
- It opens with the warning, in the warning colour, every time:
  "These settings go beyond the game's own menu. They are finicky: some can make the game look wrong, run badly or crash. Change
  them only if you know what they do. Return to Original puts every setting back."
- One card per console-only setting the client has (A6, part 2): its plain name, one line on what it does, a keep tick and a few
  chosen levels as level buttons, the game's level highlighted. No costs and no graph: these are not measured.
- A risky setting (A4) says so on its card: "Risky: put back to a safe value when you log out; hold Shift while entering the world
  to skip it."
- Below the cards, the tools that leave the minimap menu (A5): **Also use the Crowded settings in raids and battlegrounds** (a
  tick), and the buttons **Check this spot**, **Run benchmark**, **Show last report** and **Apply all now**.
- Like the other settings pages it edits the profile in use, is read-only on Original and Maximum (with the Everyday and Crowded
  buttons), and is greyed in combat and during a test.
- More cards than fit: the page shows them in columns as the other pages do; if they still do not fit, a second Advanced page
  (Advanced 2) follows. Nothing scrolls.

## A3. Turning Advanced on

- A small **Advanced** switch in the title bar, left of the rocker, shows or hides the Advanced page. Off by default; the choice is
  saved.
- The first time it is turned on, a short warning stands in the window with **I understand** and **Cancel**; only I understand
  turns Advanced on. After that the switch works at once.
- Turning Advanced off hides the page; the values already kept stay kept (they are part of the profile). Return to Original puts
  them back like every other setting.

## A4. The safety net for risky settings

- A setting marked risky in A6 is handled as picture sharpness above 100% is today:
  - when the player logs out, its value in the game's own saved settings is put back to its safe value (so a value that crashes the
    game at start cannot lock the player out), and it is applied again after entering the world;
  - holding Shift while entering the world skips every kept risky value for that session;
  - the safe value is the game menu's own highest level for that setting, or the client's default where the menu has none.
- Advanced values are kept in Everyday or Crowded like every other setting and put back at every loading screen.

## A5. The title-bar switch and the minimap menu

**The rocker** replaces the profile pill:
- Two halves, **Everyday | Crowded**, the half in use lit in its profile colour. A click on a half switches to that profile (silent,
  as on Home).
- On Original or Maximum neither half is lit, and a dot and the name in that profile's colour stand beside the rocker.
- Greyed, and inert, in combat and during a test.
- Home keeps its four profile cards.

**The minimap menu**, top to bottom:
- **Settings** (opens the window; larger and brighter than the rest).
- **Everyday**, **Crowded**, **Maximum** (names only, the one in use ticked); hovering one shows its description as today's menu
  writes it ("normal play", "raids and busy cities", "everything at its highest (about N fps)").
- **Find my best settings**, **Find my crowded settings**.
- **Return to Original** (hover: "Your own settings, from before the addon changed anything.").
- Gone from the menu: the "Profile" heading, Original as a profile line, "Save my game's current settings as..." (it is in the window's
  page list), the raid option and the Advanced submenu (both on the Advanced page now).

## A6. The settings (candidates until the probe)

Part 1, game-menu settings for the normal pages (the plain name, the page): view distance (World detail), environment detail (World
detail), particle density (Light and shadows), projected textures (Light and shadows), spell density (Light and shadows), depth
effects (Light and shadows), outline mode (Light and shadows), texture filtering (World detail), anti-aliasing (World detail). Each is
kept only where the probe and the client's menu agree it exists, with the menu's own levels.

Part 2, console-only settings for Advanced. The probe's built-in list asks about 67 names from the owner's macros; the owner adds
`ffxGlow ffxDeath ffxNether ResampleSharpness ResampleQuality MSAAQuality ffxAntiAliasingMode textureFilteringMode worldBaseMip`.

| Setting (plain name) | Console name (to confirm) | Levels (to confirm) | Risky |
|---|---|---|---|
| Ground clutter distance | groundEffectDist | menu's levels, then beyond (for example 300, 400, 500) | no |
| Bloom (glow) | ffxGlow | Off, On | no |
| Grey death effect | ffxDeath | Off, On | no |
| Weather | WeatherDensity | 0 to 3 | no |
| Particle density beyond the menu | particleDensity, particleMTDensity | menu's levels and up | no |
| Spell effects | spellClutter, graphicsSpellDensity | the client's values | no |
| Sun shafts | sunshafts | Off, Low, High | no |
| Bloom strength | graphicsBloomUserMult | a few steps | no |
| Volumetric fog | volumeFogLevel | the client's values | no |
| Reflections and refraction | reflectionMode, refraction | the client's values | no |
| Sharpening | ResampleSharpness | a few steps | no |
| View distance beyond the menu | farclip, horizonStart | menu maximum, then 2 to 3 steps up | yes |
| Object and terrain detail distances | terrainLodDist, wmoLodDist, entityLodDist, doodadLodDist, lodObjectCullSize, lodObjectMinSize | the client's default, then up | yes |
| Shadow map size | shadowTextureSize | the client's values | yes |
| Shadow cascades and softness | shadowNumCascades, shadowSoft, shadowBlendCascades | the client's values | yes |

After the probe: a setting the client lacks is dropped from that client; the levels are fixed per client from its answers and its
defaults; a setting the reddit thread or the wiki ties to crashes is risky.

## Testing

- Pure models as today: the Advanced page's model (cards, levels, the warning, the risky line, read-only, greyed), the rocker's model
  (which half is lit, the dot and name, greyed), the menu model (the new order, the hints, Return to Original), the safety net's
  logout and Shift rules for each risky setting, the first-turn-on acceptance.
- The test's window count and minutes with the new measured settings; 256 offered and dropped when the client refuses it.
- Frame tests for the page, the switch and the rocker; mutation rows for every rule, each checked killed; the full table; a fresh
  review; the owner's look in the game on both clients before release.

## Out of scope

Raytracing (decided 2026-11-02: never); measuring the Advanced settings; typed values; settings that are not graphics (frame-rate
caps, sound, interface).
