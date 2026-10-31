# ForeverSettings: install and first use

ForeverSettings measures what each graphics setting costs on **your** PC, tells you in plain words, and keeps the settings you choose. It never touches a setting while you are in combat or while a test is running, and it can put everything back.

## Install (2 minutes)

1. **Close the game.**
2. Download `ForeverSettings-0.9.0.zip`.
3. Open the game's AddOns folder. For Forever it is `World of Warcraft\_forever_\Interface\AddOns` (for the retail game, `_retail_` instead of `_forever_`).
4. Unzip the file **into that folder**. When it is right you have `...\AddOns\ForeverSettings\ForeverSettings.toc` (one `ForeverSettings` folder, not two inside each other).
5. Start the game. At character select, click **AddOns** and make sure **ForeverSettings** is ticked (tick "Load out of date AddOns" if it asks).
6. In the game you get a small button on the minimap. Click it for the menu.

## First use

1. Stand still somewhere **quiet**, with a view of some trees, water or buildings. Close browsers, video and streaming programs.
2. Minimap button, **Find my best settings**. Pick the frame rate you are aiming for (your monitor's refresh rate is a good choice). Choose **Thorough** (the window shows how many minutes each takes; Quick is shorter but cannot tell you what everything at the highest would cost).
3. Tick the box and press **Start**. Then **don't move, turn the camera, open any window or alt-tab** until it finishes. It runs on its own. The step count can grow while it runs: when the frame rate isn't steady, a reading is taken again so the result can be trusted.
4. When it ends, the results window shows what it recommends and what each change does in frames per second. **Save** keeps the choice as your *Everyday* settings.
5. Later, in a busy place (a city, a raid): **Find my crowded settings**, then Save as your *Crowded* settings.

## The four profiles (minimap menu, Profile)

- **Original**: your own settings, hands off. The addon records them before it first changes anything. Choosing Original puts them back.
- **Everyday**: the settings you saved for normal play.
- **Crowded**: the settings you saved for raids and busy cities.
- **Maximum**: everything at its highest level the addon has learned. It needs plenty of graphics memory and may cost a lot of frame rate. Switch back to Everyday any time.

**My settings** (minimap menu) shows every setting with what each level costs in frames per second, how much it matters to the picture, and what everything at the highest would give.

## If something looks wrong

- Minimap menu, **Original**: back to exactly how your game was before.
- `/fset reset` in chat: puts back everything the addon changed.
- To remove the addon: run `/fset reset` first, then delete the `ForeverSettings` folder.

## Telling me about a problem

Please send: a screenshot, what you clicked, and the version shown next to ForeverSettings in the AddOns list at character select. If a test stopped, the window says why; screenshot that too.
