# Changelog

## 0.10.1

- **Picture size** is one saved setting now. The slider and the size buttons do the same thing: letting go of the slider keeps the size in the profile in use, as a button does, and the slider and the highlighted button always show the same size. The buttons go up to 200% (125, 150, 175 and 200% are new; the test never measures them, so their cost shows "?"). "Back to normal" is now "Back to 100%", and `/fset size 50` to `/fset size 200` keeps the size too.
- Safe start for big sizes. The game saves its own settings when you quit and loads them before any addon runs, so a size above 100% that crashed your graphics card could lock you out. The addon now puts a kept size above 100% back to 100% in the game's own settings when you log out, and applies it again after you enter the world. If a saved size crashes the game when you enter, hold Shift while you enter: the addon skips it for that session.
- A test warns when the picture size is above 100%, because it spoils the numbers.
- **My settings is simpler.** The settings pages always change the profile you are using, and the change happens in the game at once. The Everyday and Crowded tabs and the buttons at the bottom of the window are gone. A coloured pill next to the close button shows which profile is in use (grey Original, green Everyday, orange Crowded, coral Maximum); click it to go to Home and switch. The Home cards carry the same colours. Original and Maximum can't be changed: their pages show your levels greyed out, with Everyday and Crowded buttons to switch to one you can edit. Save as Everyday or Crowded now says which settings it replaced.
- The minimap button has its own icon: a frame-rate gauge in the four profile colours, as on the addon's page. It also shows at the left of My settings' title bar and in the game's AddOns list, which now describes the addon in plain words.
- `/fset set` stores a setting under the name the game and the window use, whatever case you typed.
- The README now has a **Known issues and things to know** section. The ones that matter for this release: sizes above 100% can crash some graphics cards; hold Shift while you enter the world to skip a saved size above 100% for that session; and if the game won't start, set `SET RenderScale "1"` in `WTF\Config.wtf`.

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
