# Changelog

## 0.10.0

- **My settings** is a new flat window with rounded corners and a page list on the left: Home, Light and shadows, World detail, Picture size, Tests and results and About. Nothing scrolls. Home switches profile and starts or shows the tests, and the Everyday and Crowded switch sits above the settings pages.
- **Save as Everyday** and **Save as Crowded** buttons at the bottom of the page list keep the settings you have in the game now.
- **Picture size**: a slider from 50% to 200% for picture sharpness (also `/fset size 50` to `/fset size 200`, and `/fset size off`). It lasts for this session only: the game goes back to your normal setting when you log out. Above 100% it warns that some graphics cards crash at high values. The page also says whether the game's dynamic render scale is on.
- My settings shows a live total under the list: "Your Everyday settings: about N fps".
- A test warns when dynamic render scale is on, because it changes the picture size during a test and spoils the numbers. The "Before you start" list says to turn it off.
- `/fset probe` asks the game which settings it has.

## 0.9.1

- Releases are now packaged and uploaded automatically. The addon itself is unchanged.

## 0.9.0

- New profile **Maximum**: every setting at its highest level the addon has learned, from the minimap menu (with "about N fps" when your test measured it), `/fset profile maximum` or a Switch to Maximum button in My settings. It cannot be edited, says that the sharpest textures need plenty of graphics memory, and is worked out again at every loading screen, so levels learned later are picked up.
- **My settings** shows under every level what it costs in frames per second against the level you have (`+8 fps`, `-12 fps`, `now`, `same`, `?`), how much each setting matters to the picture, which test the costs come from, and what everything at the highest would give.
- A first install forces nothing.

## 0.8.0

- A guided test no longer prints in chat except safety messages and two warnings (vsync, frame-rate limit).
- The results window is rebuilt: a verdict, what each change does in frames per second, a setting list and one cost graph at a time. A Save button keeps the recommendation as your Everyday or Crowded settings, or keeps what you have now when nothing needs to change.

## 0.7.0

- Plain words instead of setting names, a new minimap menu and the My settings window.

## 0.6.0

- A busy-place test, a Quick mode for the guided test, and a check of a recommendation.

## Before 0.6.0

- The forced-settings list, the benchmark, profiles, the recommender, the crowd test and the guided window.
