# Changelog

All notable changes to Game Hub are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until a 2.0 release, the [HTTP API](docs/api.md) is internal and may change in minor versions; such changes are called out here.

## [Unreleased]

### Added

- **Settings › Made by.** Who made Game Hub, a short note from them, links to their website and the GitHub project, and **Star on GitHub**, **Give feedback** (e-mail) and **Report a problem** (GitHub issues), with the version and license. The details live in `www/brand/about.json` so a fork can swap them; only `https:` and `mailto:` links are used.
- **Release safety.** `tools\check-release.ps1` runs every code check (PowerShell 5.1 parse, ASCII, JavaScript, translations, advice tests) and a privacy scan of what Git would publish. It refuses settings, data, logs and backups, and any text containing your user name, PC name, user folder, game install folders, game folders, distinctive drive labels, backup folder, a non-noreply Git e-mail, lines from your own `release-denylist.txt`, or anything shaped like a token or private key. The list is built on your PC each time and never stored. `.githooks/pre-commit` runs it on every commit (`git config core.hooksPath .githooks`).
- **Release zips from Git.** `tools\make-release.ps1 -Version x.y.z` checks the tree is committed, takes the notes from this changelog, runs the release check, and builds `dist\GameHub-x.y.z.zip` with `git archive` (so only committed files ship) plus its SHA-256. `-Publish` creates the GitHub release.
- The repository is [izored/gamehub](https://github.com/izored/gamehub): issue links, the translation form and the changelog links point there.
- **Controller support** (`www/gamepad.js`). See [Using a controller](docs/usage.md#using-a-controller).
  - Works with DualSense, DualShock 4 and Xbox controllers, over USB or Bluetooth, and with DS4Windows' virtual Xbox controller.
  - All connected controllers are merged into one, so a DualShock 4 seen twice through DS4Windows never acts twice.
  - Buttons: the D-pad or left stick moves between cards, rows, tabs and buttons. ✕/A plays or presses, ○/B goes back, △/Y toggles Favorites and □/X opens the edit dialog. L1/R1 switch tabs, Options/Menu opens Settings, and the right stick scrolls.
  - A bar of button hints shows PlayStation symbols or Xbox letters, to match the controller. Focus stays on the same card after re-renders.
  - Input is ignored while Game Hub isn't the window in front, and a button still held when it comes back does nothing. Moving the mouse hands control back to the mouse.
- **While you play** (`watch-game.ps1`). See [While you play](docs/usage.md#while-you-play).
  - After a launch, Game Hub minimizes as soon as the game's main window opens, so the keyboard, mouse and controller go straight to the game.
  - **Boot screens.** The small boot or splash screens many games show first (anti-cheat, launcher, logo) are skipped: a window counts at once from 960×540. A smaller window counts after 30 seconds as the game's only window.
  - **Slow starts.** If no window has appeared after 90 seconds, Game Hub minimizes anyway, and brings the game's window to the front once it opens.
  - It comes back to the front a few seconds after the game has fully closed.
  - This works for every launcher: a game's processes are the programs inside its install folder.
- **Settings › While you play:** two switches for these behaviours, also available as `minimizeOnLaunch` and `restoreAfterGame` in `config.json`. Both default to on, including for an existing `config.json` that doesn't have the keys.
- **Settings › Controllers:** the controller buttons, plus a reminder for Steam games. If a Steam game ignores your controller, turn Steam Input on for that game in Steam, or leave it off when you use DS4Windows.
- `logs\watch.log` records each launch watch: boot screens, the game window, minimize and restore. `watch-game.ps1 -List` checks that the Game Hub window can be found.
- Docs:
  - [usage](docs/usage.md) gains controller and *While you play* sections, with a note on why games treat USB, Bluetooth and DS4Windows differently, and the Steam Input reminder;
  - [troubleshooting](docs/troubleshooting.md) gains a *A Steam game doesn't see my controller* checklist and more new entries;
  - the [architecture](docs/architecture.md#the-launch-watcher-watch-gameps1) page explains the launch watcher.
- **First-run setup page.** It replaces editing `config.json` before the first launch. See [The setup page](docs/usage.md#the-setup-page).
  - Step 1: the drives Game Hub must never read. USB and removable drives are ticked for you, including USB SSDs that Windows reports as fixed. Only each drive's name and size are read on this page.
  - Step 2: game folders. Folders Steam and the Xbox app fully manage are listed as covered; the folders of the other launchers, and top-level folders whose name looks like a game folder, are suggested and ticked. *Add folder...* adds any other.
  - Step 3: start with Windows, minimize and restore while you play, language, and the lock (only when the PC has other accounts).
  - Nothing is scanned until you click *Scan my games*. The first scan no longer starts on its own.
- **Find your game folders with an AI** (setup page and Settings › Game folders). Game Hub writes a prompt for any AI assistant, naming the drives to stay away from, the folders already covered and the folders already in Game Hub. You paste the answer back; every path in it is checked (it exists, is not on a never-read drive, is not already covered, is not inside another folder, is not a whole drive or Windows folder) and only folders that pass can be added. The AI provider sees folder names, nothing else.
- **Settings › Drives:** choose the drives Game Hub never reads from the page (`excludeDriveLetters`), then save and rescan.
- **Play time.** See [Play time](docs/usage.md#play-time).
  - Every game started from Game Hub records its play session (start, end, minutes) in `data\sessions.jsonl`. Sessions under a minute are ignored.
  - Steam's own play time is imported from its local settings (`localconfig.vdf`), so Steam games show their full history from day one.
  - Cards and the billboard show the hours played; a **Most played** row joins the home page.
  - **Sort by** in every grid (all games, a launcher, a drive, search results): name, most played, recently played, recently added, size. The choice is remembered.
  - Optional: **Count games started outside Game Hub** (Settings › While you play, `trackOutsideLaunches`, off by default). `track-games.ps1` checks once a minute which games are running. A game is never counted twice.
- **More launchers:** GOG Galaxy, Battle.net, Riot Client, Amazon Games, Rockstar Games Launcher, and the Xbox app (Microsoft Store and PC Game Pass games). Each has its own tab when you have games there. Details in [Launchers](docs/launchers.md).
- **Backups of Game Hub.** See [Backups](docs/usage.md#backups).
  - Once a day, when something changed, Game Hub saves `config.json`, `overrides.json`, the game list with every game's folder, favorites and launches, play time, game window titles and custom covers to a zip in `data\backups`, with a `my-games.csv` inside. Game files and game saves are not included.
  - It keeps every backup of the last 48 hours (up to 20), one per day for 7 days and one per week for 4 weeks.
  - Settings › Backups: the list, **Restore** (the current state is backed up first, so a restore can be undone), **Back up now**, **Also copy backups to** another folder (`backupCopyTo`), and **Download my games list (CSV)**.
  - **Self-repair:** at startup, a settings or data file left empty, zeroed or unreadable by a crash or a power cut is put back from the newest good backup, and a banner on the page says so.
- **Lock Game Hub to your Windows account** (optional, `lockToAccount`, off by default). Settings › Security only appears when the PC has other user accounts. See [SECURITY.md](SECURITY.md#optional-lock-to-your-windows-account).
- **DS4Windows rules per game** (Settings › Controllers and the Edit dialog, only when DS4Windows is installed): keep DS4Windows on, turn it off, or use one of its profiles while each game runs. Game Hub writes DS4Windows' own *Auto Profiles* rules, matching the game's folder and, for games with anti-cheat, its window title, then restarts DS4Windows. See [Controllers](docs/controllers.md#ds4windows-rules-per-game).
- **Which games need DS4Windows?** Settings › Controllers suggests, for every game, whether DS4Windows should stay on or turn off, and says why. See [Controllers](docs/controllers.md#which-games-need-ds4windows).
  - **Your controllers:** Game Hub reads from Windows which PlayStation controllers are connected or paired, and how (USB or Bluetooth). You can change it.
  - **Check my games** (only when you press it, `check-controllers.ps1`) looks each game up on PCGamingWiki and Steam's store, and looks for Sony's controller library in the game folder. Only game names and Steam app numbers are sent.
  - **Steam Input:** for Steam games, Game Hub reads Steam's own per-game setting.
  - **Use the suggestions** fills in every choice that has a suggestion; DS4Windows changes only when you apply.
  - **Your answer wins:** after you play a game whose suggestion is unsure, Game Hub asks once how the controller worked, and **Tell Game Hub** does the same for any game at any time. Answers are kept in `data\controller-feedback.json` and included in backups.
  - A tip appears when DS4Windows also takes over your DualSense, which most games understand by themselves.
  - `tools/test-pad-advice.js` checks the suggestion rules.
- **On-screen keyboard** for controllers: Share / View opens it for the search box or the text field in focus.
- **Bring Game Hub back with the controller:** hold View + Menu (Share + Options through DS4Windows) for 1.5 seconds anywhere in Windows (`controller-helper.ps1`, `controllerSummon`, on by default).
- **Languages:** the page is available in English, French, Spanish, Portuguese (Brazil), German, Russian, Simplified Chinese, Japanese, Korean, Polish and Turkish (`www/lang/`). It follows the browser's language, or the one chosen in Settings › Language (`language`). The 10 non-English languages were translated by an AI and say so in Settings, with a link to report a wrong translation. Missing text falls back to English.
- `tools/check-translations.ps1` checks that every text the page uses exists in English and that translations keep their placeholders.
- Docs: [Controllers](docs/controllers.md) (Xbox, DualSense and DualShock 4 in Game Hub and in games, Steam Input, DS4Windows, double input, USB or Bluetooth), [Staying safe](docs/staying-safe.md) (general security advice for gaming PCs), [Translating](docs/translating.md), and a *Wrong or missing translation* issue form.

### Changed

- **Your data now lives apart from the program,** in `%LOCALAPPDATA%\GameHub`: `config.json`, `overrides.json`, `data\` and `logs\`. The program folder holds nothing personal, so it can be anywhere (even Program Files), replaced whole by an update, or published. The first start after updating copies the old files over, checks every one arrived, and leaves the originals with a `DATA-MOVED.txt` note; delete them once everything works. **Settings › Backups** shows the folder. A `portable.txt` file next to `server.ps1` keeps the data in the program folder (USB drives, development copies), and `GAMEHUB_DATA` names another folder. See [Where your data lives](docs/installation.md#where-your-data-lives). Scripts take `-Root` for the program folder as before.
- **Install folder.** The docs now suggest `%LOCALAPPDATA%\Programs\GameHub` for the program, and the release zip from the GitHub releases page.
- **Billboard slideshow.** With no favorite picked, the billboard starts on the featured game, then moves through the Game Hub banner and every game in the library, in a new shuffled order each round, one every 2 seconds. No game is named in the code: it uses whatever each library has, and games without wide art appear on a blurred version of their cover or icon. It holds still while the pointer or controller focus is on it, so Play, Open folder and the pen always act on the game you see. It also holds while a dialog is open, the page is scrolled down or hidden, or Windows is set to reduce animations. With no games yet, the billboard shows the Game Hub banner instead of disappearing.
- **Brand assets in one folder,** `www/brand/`: `logo.svg`, `favicon.svg`, `icon.ico` (the shortcut icon, previously `gamehub.ico` at the root), `banner.svg` (a placeholder for now) and `brand.css` (colours, fonts, radius and shadow, moved out of `style.css`). Replace a file under the same name to rebrand; [its README](www/brand/README.md) gives sizes and where each one shows. `install-shortcuts.ps1` only draws the icon when it is missing, and the server serves `/brand/*`. The look is unchanged.
- **Billboard follows your favorites.** Pointing at a card in the Favorites row, or moving to it with a controller, shows that game on the billboard: its background, logo, details and play time, with a short crossfade. It stays until you point at another favorite, so the billboard's Play button plays the game you were looking at. A favorite without background art gets its wide header or a blurred icon. See [the home page](docs/usage.md).
- **Controller on Home:** moving between the billboard buttons and the Favorites cards no longer scrolls the page and shrinks the billboard. The page only scrolls when you move to another row, or when the Favorites row does not fit in a short window.
- `open-hub.ps1` opens Game Hub as a Microsoft Edge app window when Google Chrome isn't installed, instead of a normal browser tab. Both browsers are looked up for the current user as well as machine-wide.
- **API.** `GET /api/settings` and the response of `POST /api/settings` include `minimizeOnLaunch` and `restoreAfterGame`, and `POST /api/settings` accepts them. `POST /api/launch` starts the launch watcher.
- **No more VBScript.** Shortcuts start Game Hub with the console host's hidden mode (`conhost.exe --headless`, Windows 10 2004 and later), because Windows is phasing VBScript out. `gamehub.vbs` stays as the fallback on older Windows. Run `install-shortcuts.ps1` again to update existing shortcuts.
- The launch watcher now runs after every launch, to record play time, even with both *While you play* switches off. It also remembers each game's window title (`data\game-windows.json`) for the DS4Windows rules.
- `config.example.json` gains `language`, `trackOutsideLaunches`, `controllerSummon`, `lockToAccount` and `backupCopyTo`, and its `gameRoots` is just `C:\Games`: the setup page fills in the rest.
- **API** (internal, see [HTTP API](docs/api.md)):
  - new: `GET /api/setup/drives`, `POST /api/setup/folders`, `POST /api/setup/check`, `POST /api/setup/finish`, `GET /api/backups`, `POST /api/backups/create`, `POST /api/backups/restore`, `GET /export/my-games.csv`, `GET` and `POST /api/ds4windows`, `GET /lang/<file>`;
  - `GET /api/games` adds `playtime` and `extra` (`needsSetup`, `notes`, `language`); games gain `steamMinutes` and, for Xbox app games, `storeId`;
  - `GET` and `POST /api/settings` add `drives`, `excludeDriveLetters`, `trackOutsideLaunches`, `controllerSummon`, `language`, `lockToAccount`, `otherAccounts`, `backupCopyTo` and `ds4windows`; `POST /api/game/save` accepts `ds4`;
  - error responses add a `code` (and sometimes an `arg`) so the page can show them in the chosen language.
- **DS4Windows API:** `GET /api/ds4windows` adds `controls`, `wraps`, `hides`, `pads`, `facts`, `checkedAt`, `progress`, `checking` and `feedback`; new `POST /api/ds4windows/check` and `POST /api/ds4windows/feedback`; `POST /api/settings` accepts `pads`. `config.json` gains the optional `pads` and `ds4windowsFolder`.
- Started from PowerShell 7 (for example from Windows Terminal), Windows PowerShell inherits PowerShell 7's module folders and can fail to load its own modules. The server now removes those folders from its module path at startup.

### Security

- The launch watcher reads only window titles and executable paths, using *query limited information* rights. It never opens, reads or stops a process, and it only minimizes and restores browser windows titled exactly `Game Hub`. The game id it receives must match `[A-Za-z0-9._-]+`.
- **Optional lock:** `data\session.key` holds a random 256-bit key readable only by the account that runs Game Hub (plus SYSTEM and administrators); `open-hub.ps1` swaps it for an `HttpOnly`, `SameSite=Strict` cookie. Every API, artwork and export request then needs that cookie (401, code `locked`). If the key cannot be created, the lock is switched back off and the page shows an error instead of pretending to be locked.
- New launcher links are allowlisted exactly: `battlenet://`, `amazon-games://`, and `shell:AppsFolder\<package>!<app>` for Xbox app games, which starts through Windows Explorer.
- The setup page and the folder check never read a never-read drive: drives are described from Windows' own drive list, and folder suggestions only list top-level folder names on allowed fixed drives.
- A restore only writes Game Hub's own files listed in the backup (`config.json`, `overrides.json`, files in `data\` and custom covers), never a path taken from the zip.
- DS4Windows: Game Hub only changes the rules it wrote itself (listed in `data\ds4windows-managed.json`) and keeps a copy of the previous rules file in `data\backups`. It never changes DS4Windows' other settings, and never restarts a DS4Windows whose settings folder isn't the one it wrote to.
- Check my games runs only when you press it and sends only game names and Steam app numbers.

## [1.0.0] - 2026-11-21

First public release.

### Added

#### Library scanning

- **Steam:** every library listed in `libraryfolders.vdf`. Includes size on disk, last-played time and Steam's locally cached artwork.
- **Epic Games:** launcher manifests. Epic installs the launcher no longer knows about are still found through their `.egstore` folder, start from their executable, and carry a re-link hint.
- **EA app / Origin:** detected through `__Installer\installerdata.xml` and EA uninstall entries. The real executable comes from the installer data, preferring full versions over trial executables.
- **Ubisoft Connect:** found through the launcher's registry.
- **Game folders (`gameRoots`):** every sub-folder is a game.
- **Discovery:** uninstall-registry folders and Program Files, using engine fingerprints (Steamworks, Unity, Unreal `Paks`, EOS, Bink, FMOD, DLSS/XeSS, anti-cheat folders and more), with built-in exclusions for non-game vendors.
- **Executable picking:** depth, name similarity and size ranking, skipping installers, redistributables, crash reporters, anti-cheat services, updaters and overlays.
- **Excluded drives** by letter or volume label are never read. Only fixed disks are scanned.
- **Icons:** extracted from each executable as a 256 px PNG with real alpha.
- **Atomic writes:** `data/games.json` is written atomically, and `skipped[]` lists folders without a usable executable.

#### Launching

- Steam (`steam://rungameid/…`), Epic (`com.epicgames.launcher://…?action=launch`) and Ubisoft (`uplay://launch/…`) games start through their launcher.
- Everything else starts from its executable, with optional arguments and the executable's folder as the working directory.
- Per-game executable override. A custom executable wins over the launcher link, and can be reset to the default.

#### Interface

- Netflix-style home page:
  - a featured billboard: newest install, otherwise last played;
  - **Favorites** on 16:9 cards (wide art with the title logo), in the order they were starred;
  - **Continue playing** and **Recently added**;
  - one row per launcher, ordered by how many games each has.
- Tabs per launcher, a per-drive view (`#/d/<letter>`) and an all-games grid (`#/all`). Every view has its own bookmarkable address.
- Instant search across name, launcher, drive and path. It ignores accents. `/` or `Ctrl+K` to focus, `Enter` launches the first result, `Esc` clears.
- Card hover actions: play, favorite, open folder, edit. A **NEW** badge marks recent installs, and a ⚠ shows warnings.
- **Storage** overview per drive: games, other data, free space.
- **Cleanup** panel for duplicate installs (`duplicateOf`) and leftovers listed in `overrides.json`, with sizes and the copy to keep. Nothing is ever deleted automatically.
- **Edit dialog** (pen icon):
  - name, executable with a native file picker, and launch arguments;
  - Steam artwork search; cover and background upload; drag-and-drop;
  - hide from hub.
- **Settings page:**
  - rescan, add a game, fetch missing covers;
  - game folders with a native folder picker;
  - hidden games;
  - start with Windows.
- Monochrome black-and-white theme. Colour comes only from game art.
- Keyboard navigation throughout. Toasts announce results to screen readers.
- First-run experience: `config.json` is created from `config.example.json` and the first scan starts automatically while the page waits.

#### Artwork

- Automatic download after every scan:
  - **Steam:** exact title match only; 600×900 cover, hero, logo.
  - **Microsoft Store:** through `msStoreId`.
  - **Epic:** key art from the Epic launcher's local catalog cache.
- Misses are cached in `data/covers/_misses.json`. `fetch-covers.ps1 -Force` retries them.
- Custom uploads (JPEG, PNG or WebP, up to 25 MB) always win over downloaded art.
- Every downloaded or uploaded image is checked by its file signature.

#### Setup

- `install-shortcuts.ps1` creates Desktop, Start menu and Startup shortcuts, plus a generated icon.
- `gamehub.vbs` runs everything without console windows.
- `open-hub.ps1` starts the server if needed and opens a Chrome app window, falling back to the default browser.
- Works with Windows PowerShell 5.1 and no administrator rights.
- Two setup paths:
  - a step-by-step manual [setup guide](docs/setup-guide.md);
  - an AI-assisted setup: [`AGENTS.md`](AGENTS.md) is a playbook any AI assistant can follow to install Game Hub, scan and link the user's games, with the user's approval at each step. `CLAUDE.md` points Claude Code to it, and [docs/setup-with-ai.md](docs/setup-with-ai.md) explains how to use it with an agent or a chat assistant.

### Security

- The server binds to `127.0.0.1` only, and requests must be addressed to `localhost`/`127.0.0.1` on the configured port. This prevents DNS rebinding.
- POST requests need an `X-GameHub: 1` header and are refused if they come from another origin. This prevents cross-site request forgery.
- Games are launched by catalog id only. Launcher links must use an allowlisted scheme: `steam`, `uplay`, `com.epicgames.launcher` or `origin2`.
- Static and artwork files are served with path-traversal checks and `X-Content-Type-Options: nosniff`.
- Executable and folder paths on excluded drives are refused before they are touched.
- The web app never inserts game data as HTML.

[Unreleased]: https://github.com/izored/gamehub/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/izored/gamehub/releases/tag/v1.0.0
