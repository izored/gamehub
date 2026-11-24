# Brand assets

Every Game Hub brand asset lives in this folder. To rebrand, replace a file with your own version **under the same name**, then reload the hub (Ctrl+R). Nothing else needs editing.

| File | What it is | Format and size | Where it shows |
|---|---|---|---|
| `logo.svg` | The Game Hub mark | SVG, square (drawn on a 64 × 64 grid). Should stay readable at 30 px. | Top bar, next to the name; the "Game Hub is locked" page |
| `favicon.svg` | The tab and app-window icon | SVG, square. Keep it simple: it's shown at 16 to 32 px. | Browser tab; the Game Hub app window and its taskbar button |
| `icon.ico` | The Windows shortcut icon | ICO with 256, 64, 48, 32 and 16 px frames (PNG frames are fine) | Desktop, Start menu and Startup shortcuts |
| `banner.svg` | The Game Hub banner. **Today it's a placeholder.** | SVG or a picture, 1920 × 720 (8:3). Keep the important part in the middle 60%: wide windows crop the sides. | One slide of the home page billboard's slideshow each round; the billboard of an empty library. Once the real banner is ready, it can also go at the top of the [README](../../README.md) |
| `brand.css` | Colours, fonts, corner radius and shadow | CSS variables | The whole interface: `style.css` uses these variables |
| `about.json` | Who made Game Hub: `name`, `role`, `website`, `repo`, `feedback` (a `mailto:` or `https://` link), `version`, `license` | JSON. Links must start with `https://` (`feedback` may be `mailto:`). | **Settings › Made by**. `repo` is also where the page sends problem reports and translation fixes. `tools\make-release.ps1` checks `version` matches the release |

## Notes for each file

- **Banner as a picture.** To use a PNG, JPG or WebP instead of SVG, save it here (for example `banner.jpg`) and change the `BANNER` constant in `www/app.js` (and the README, if you put the banner there).
- **Shortcut icon.** Windows copies the icon into each shortcut when the shortcut is made. After replacing `icon.ico`, run `install-shortcuts.ps1` again so the shortcuts pick it up. If Windows still shows the old icon, it's its icon cache: signing out and back in refreshes it. When `icon.ico` is missing, `install-shortcuts.ps1` draws the default one here.
- **Colours.** Game Hub is monochrome on purpose: black, white and greys, with colour coming from game art only. `--warn` (amber) and `--danger` (red) carry meaning and should stay recognisable as warning and error. A few scrims over artwork in `style.css` use the background colour as `rgba(14, 14, 14, …)`. If you change `--bg`, search `style.css` for `14, 14, 14` and update those too.
- **Fonts.** The fonts are Windows' own (Segoe UI Variable, Cascadia Mono), so nothing is downloaded. A custom font file would go in this folder, with an `@font-face` rule in `brand.css`.
- **GitHub social preview.** It isn't stored in the repo: upload a 1280 × 640 picture in the repository's Settings › General › Social preview.

## The name "Game Hub"

The name is text, not an asset, so it isn't in this folder:

- it's written into every translation in `www/lang/*.json`;
- the page title in `www/index.html` must stay exactly **Game Hub**, because `watch-game.ps1` finds the Game Hub window by that title to minimize and restore it while you play.

Renaming the app therefore means changing the translations, the page title and the window match in `watch-game.ps1` together.
