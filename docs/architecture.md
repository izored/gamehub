# Architecture

Game Hub is three plain-text pieces with no build step and no dependencies:

- PowerShell scripts that **scan** your drives;
- a PowerShell **server**;
- a vanilla JavaScript **web app**.

Everything runs as the logged-in user, on `127.0.0.1`.

```
                 ┌───────────────────────────────────────────────────────┐
  Desktop /      │  conhost --headless (or gamehub.vbs) ──► open-hub.ps1 │
  Start menu ───►│     starts server.ps1 if nothing answers,             │
                 │     opens http://localhost:8790 (Chrome/Edge app)     │
                 └───────────────────────────────────────────────────────┘
  Startup  ───►  conhost --headless (or gamehub.vbs server) ──► server.ps1  (hidden, single instance)

 ┌─────────────────────────┐   HTTP (localhost only)   ┌──────────────────────────────┐
 │ www/  (index.html,      │ ◄───────────────────────► │ server.ps1                   │
 │  app.js, gamepad.js,    │  GET /api/games, POST ... │  System.Net.HttpListener     │
 │  style.css, lang/*.json)│                           │  serves www/, art, covers    │
 │  renders the hub        │                           │  launches games ─────────────┼──► watch-game.ps1, one per launch:
 └─────────────────────────┘                           │  edits overrides.json        │    records play time, minimizes the
                                                       │  daily backups, self-repair  │    hub while the game runs, restores it
                                                       │  DS4Windows rules            │
                                                       │  starts helpers ─────────────┼──► controller-helper.ps1 (View + Menu)
                                                       │                              │    track-games.ps1 (optional)
                                                       │  runs ONE background job ──┐ │
                                                       └────────────────────────────┼─┘
                                                                                    ▼
             config.json ──► scan-games.ps1 ──► data/games.json, data/art/*
           overrides.json ──►      │
                                   └──► fetch-covers.ps1 ──► data/covers/*
                                          (lib/steam-art.ps1, lib/store-art.ps1)
```

## Files

```
├─ server.ps1             HTTP server: static files, JSON API, launching, edits, setup page, backups
├─ scan-games.ps1         builds data/games.json (+ icons and Steam cache art in data/art)
├─ fetch-covers.ps1       downloads missing artwork into data/covers
├─ watch-game.ps1         after a launch: records play time, minimizes the hub, restores it when the game closes
├─ track-games.ps1        optional: records play time of games started outside the hub
├─ controller-helper.ps1  View + Menu on a controller brings the hub back (XInput)
├─ check-controllers.ps1  "Check my games": what each game understands by itself (PCGamingWiki, Steam, game folder)
├─ lib/
│  ├─ steam-art.ps1       Steam store search, asset lookup, image download + validation
│  ├─ store-art.ps1       Epic local catalog cache, Microsoft Store catalog
│  ├─ setup.ps1           drive list, launcher folders, folder suggestions and checks (setup page)
│  ├─ playtime.ps1        play sessions (data/sessions.jsonl), game window titles
│  ├─ windows.ps1         window and process helpers shared by the watcher, tracker and controller helper
│  ├─ backup.ps1          backups, restore, self-repair, games list CSV
│  ├─ paths.ps1           where your data lives (%LOCALAPPDATA%\GameHub, portable.txt, GAMEHUB_DATA), moving an older version's data
│  ├─ lock.ps1            optional lock to the Windows account
│  ├─ ds4windows.ps1      DS4Windows Auto Profiles rules, what DS4Windows takes over
│  ├─ controllers.ps1     your PlayStation controllers, Steam Input per game, controller facts and answers
│  └─ shortcuts.ps1       hidden start (conhost --headless, VBScript fallback) for shortcuts
├─ open-hub.ps1           start server if needed, open the page (Chrome or Edge app window)
├─ gamehub.vbs            hidden start on Windows 10 versions older than 2004
├─ install-shortcuts.ps1  creates Desktop / Start menu / Startup shortcuts with www/brand/icon.ico (draws it if missing)
├─ tools/
│  ├─ check-release.ps1       every check below, plus the privacy scan of what git would publish
│  ├─ make-release.ps1        builds dist/GameHub-<version>.zip from git (optionally publishes it)
│  ├─ check-translations.ps1  checks www/lang against the texts the page uses
│  └─ test-pad-advice.js      checks the DS4Windows suggestion rules (node)
├─ .githooks/pre-commit   runs check-release.ps1 -Staged (git config core.hooksPath .githooks)
├─ www/
│  ├─ index.html          markup for every view and dialog
│  ├─ app.js              all client logic (no framework)
│  ├─ gamepad.js          controller support: spatial navigation, button hints, on-screen keyboard
│  ├─ pad-advice.js       DS4Windows suggestions: on or off per game, and why
│  ├─ style.css           the monochrome, Netflix-style theme (layout; colours and fonts come from brand/brand.css)
│  ├─ lang/               en.json and 10 translations, index.json lists them
│  └─ brand/              every brand asset, swappable: logo, tab icon, shortcut icon, banner, colours and fonts (see its README)
├─ config.example.json    template for config.json (copied on first run)
├─ overrides.example.json documented example of overrides.json
└─ docs/                  this documentation
```

Not in the program folder at all: `config.json`, `overrides.json`, `data/` and `logs/` live in the [data folder](installation.md#where-your-data-lives), `%LOCALAPPDATA%\GameHub`, one per Windows account. The program folder can be replaced, shared or read-only. Every script starts by calling `Initialize-HubData` (`lib/paths.ps1`), which returns that folder; the first one to start after updating from a version that kept the data next to the scripts copies it over.

Not in git either: `dist/` (release zips), `DATA-MOVED.txt`, `portable.txt`, and `gamehub.ico` at the root (where the shortcut icon lived before `www/brand/`).
## The scanner (`scan-games.ps1`)

A batch job that rebuilds the whole catalog each time. A typical library takes 10–60 seconds, mostly spent measuring folder sizes.

1. **Drives.** List fixed disks, minus excluded letters and labels. Nothing outside this list is read.
2. **Launcher records.** Steam manifests (plus Steam's play time from `localconfig.vdf`), Epic manifests, the Ubisoft, GOG and Rockstar registry keys, Battle.net and Amazon Games uninstall entries, the Riot Client's install list, and Xbox app packages. See [Launchers](launchers.md).
3. **Folders.** Sub-folders of `gameRoots`; then uninstall-registry folders and `discoverRoots` sub-folders that contain engine files.
4. **Manual additions** from `overrides.json`.
5. **For each game:**
   - claim the folder (first source wins);
   - apply overrides;
   - pick an executable;
   - extract its icon (a small C# helper using `PrivateExtractIcons`, saving a 256 px PNG with real alpha);
   - copy Steam's cached artwork;
   - measure the size;
   - build the `launch` record.
6. **Write `games.json` atomically:** write to `.tmp`, then rename.
7. **Run `fetch-covers.ps1`,** unless started with `-NoCovers`.

Duplicates and cleanup items are not detected automatically. You declare them in `overrides.json`, and the scanner only measures and reports them. Deciding which copy of a game is the one in use needs judgement: play history, save files, crash logs.

## The server (`server.ps1`)

- **`System.Net.HttpListener`** on `http://127.0.0.1:<port>/` and `http://localhost:<port>/`. This needs no administrator rights or URL reservation.
- **Single instance per port,** through a named mutex `Local\GameHubServer-<port>`. A second copy exits at once.
- **A plain synchronous loop.** One request at a time is enough for one user. Long work (scan, cover fetch) runs in a separate hidden `powershell.exe` process, the **background job**, and only one job runs at a time. The UI polls `/api/status` until it's done.
- **No caching layer.** `games.json`, `state.json` and `overrides.json` are re-read from disk when needed and written atomically. `config.json` is read once at startup.
- **At startup** it repairs any of its own files left empty or unreadable by a crash (from the newest good backup), makes the daily backup if one is due, and starts the background helpers whose option is on. Started from PowerShell 7, it first removes PowerShell 7's module folders from its module path, which Windows PowerShell would otherwise inherit.
- **On a fresh install** (no `games.json`), it scans nothing: the page shows the setup page, and `POST /api/setup/finish` starts the first scan.
- **Runs in the user session, not as a service,** because games must start on the user's desktop. The Startup-folder shortcut gives it the same "always ready" feel.

See [HTTP API](api.md) for the endpoints and [SECURITY.md](../SECURITY.md) for the request checks.

## The launch watcher (`watch-game.ps1`)

A web page can't minimize or focus its own window, so this part runs outside the page. After every launch, the server starts one hidden watcher for that game. A named mutex, `Local\GameHubWatch-<id>`, keeps it to one watcher per game. Minimizing and restoring follow the two *While you play* options; play time is always recorded.

1. **Wait for the game.** A game's processes are the ones whose executable is inside its install folder. That works the same for Steam, Epic, EA, Ubisoft and standalone games, and for launchers that start the real executable a few seconds later. The watcher gives up after 5 minutes if nothing starts.
2. **Wait for the real window, then step aside.** Many games first show a small boot or splash screen: anti-cheat, launcher, logo.
   - **When it acts:** as soon as a game process has a window of at least 960×540. A smaller window counts once it has been the game's only window for 30 seconds. With no game window after 90 seconds, it acts anyway.
   - **What it does:** it minimizes the Game Hub window, and Windows then activates the next window, which is the game. The watcher also asks Windows to bring the game to the front.
   - **Late windows:** a game window that opens after the 90-second fallback is brought to the front once, when it appears.
3. **Wait for the quit.** The game counts as closed after three checks in a row, two seconds apart, find none of its processes. That way, a game that restarts itself or hands over from its own launcher isn't mistaken for a quit.
4. **Come back.** It restores the Game Hub window and brings it to the front.
5. **Record the session.** It appends the session (from the first game process to the last) to `data\sessions.jsonl`, unless it was shorter than a minute. It also remembers the game's main window title in `data\game-windows.json`, for the DS4Windows title rules.

While it watches a game, the watcher holds a second mutex, `Local\GameHubSession-<id>`. The outside-launch tracker takes the same one, so a session is recorded once, by whichever got there first.

**The Game Hub window** is a Chrome, Edge, Brave, Vivaldi, Opera or Chromium window titled exactly `Game Hub`. That's the app window `open-hub.ps1` opens. A Game Hub tab inside a normal browser window has a longer title, so it's left alone. No other window is ever touched.

**What it reads.** Window titles, and each process's executable path. The path is read with *query limited information* rights, which Windows grants even for games protected by anti-cheat. The watcher never opens, reads or stops any process.

Every step goes to `logs\watch.log`. `watch-game.ps1 -List` prints the Game Hub windows it can see and the window in front, for troubleshooting.

## Background helpers

Both are hidden `powershell.exe` processes started by the server, with a single-instance mutex each. They re-read `config.json` and stop on their own when their option is turned off.

- **`controller-helper.ps1`** (`controllerSummon`, on by default) reads controllers through XInput (`xinput1_4.dll`): every 60 ms while one is connected, every 1.5 s otherwise. View + Menu held for 1.5 s brings the Game Hub window to the front (restore, then a foreground request with the input of the current foreground thread attached, which Windows accepts), or runs `open-hub.ps1` if no Game Hub window exists. XInput sees Xbox controllers and anything presented as one (DS4Windows, Steam Input), not a PlayStation controller on its own.
- **`track-games.ps1`** (`trackOutsideLaunches`, off by default) lists running programs' paths once a minute and matches them to games by install folder, like the watcher. A game seen running starts a session; one gone for a check ends it. It reads executable paths only.

## Backups and self-repair (`lib/backup.ps1`)

- **What:** `config.json`, `overrides.json`, `data\games.json`, `data\state.json`, `data\sessions.jsonl`, `data\game-windows.json` and custom covers, zipped with `System.IO.Compression` into `data\backups\gamehub-<date>_<time>.zip`, with `backup-info.json` (time, reason) and `my-games.csv`.
- **When:** checked at startup and every 6 hours; written only when the files' fingerprint (names, sizes, times) changed since the last backup. Copied to `backupCopyTo` when set.
- **Pruning:** every backup of the last 48 hours (up to 20), the newest per day for 7 days, the newest per ISO week for 4 weeks.
- **Restore** backs up the current state first, then extracts only the allowlisted names above, never a path chosen by the zip.
- **Self-repair** runs before the server reads its settings: if `config.json`, `overrides.json`, `data\games.json` or `data\state.json` is empty, all zero bytes or not valid JSON, it is kept as `<file>.damaged` and replaced by the newest backup copy that is valid. A `config.json` with no good copy is replaced by `config.example.json`.

## Optional lock (`lib/lock.ps1`)

With `lockToAccount` on, `data\session.key` holds 32 random bytes (hex), and its access list is reduced to the current user, SYSTEM and Administrators, with inheritance removed. `open-hub.ps1`, running as that user, reads it and opens `/?k=<key>`; the server answers with an `HttpOnly`, `SameSite=Strict` cookie and a redirect. Every data and action request then needs the cookie. Another account on the same PC can reach the port (it is the same machine) but cannot read the key. See [SECURITY.md](../SECURITY.md#optional-lock-to-your-windows-account).

## DS4Windows rules (`lib/ds4windows.ps1`)

DS4Windows switches profiles, or turns itself off, according to the program in front, using rules in `Auto Profiles.xml` (in `%APPDATA%\DS4Windows`, or next to `DS4Windows.exe` for a portable copy). For each game with a choice, Game Hub writes one rule whose path starts with `^` (any program inside the game's folder) and, when it knows the game's window title, one title rule, for games whose anti-cheat hides their program path. Rules it wrote are listed in `data\ds4windows-managed.json`, so a rewrite only replaces those; the previous file is copied to `data\backups`. DS4Windows reads the file only at startup, so Game Hub restarts it when it is running (close its window, wait, then start it again).

**Suggestions** (`www/pad-advice.js`, a pure function shared with `tools/test-pad-advice.js`). For each game and each PlayStation controller you use that DS4Windows takes over, it decides whether the game reads that controller by itself over that connection. It takes, in order: your answer, PCGamingWiki's models and USB / Bluetooth fields, Steam's labels, Sony's controller library in the game folder, then Steam Input for Steam games. *Reads it itself* or *Steam Input on* means off; *Xbox only* means on. Controllers that disagree give *Depends on the controller*. The facts come from `check-controllers.ps1` (`data\controller-support.json`), started only from the button; Windows' device list (`Win32_PnPEntity`, Sony's USB vendor id) and Steam's `localconfig.vdf` are read on each request by `lib/controllers.ps1`.

## The web app (`www/`)

- One page, two scripts, one stylesheet: plain DOM, a tiny `h()` element helper, no framework and no bundler. `gamepad.js` loads after `app.js` and uses its globals.
- **State** lives in a single object `S`: catalog, favorites, launches, play time, artwork list, route, search text, sort order. Every change calls `render()`, which rebuilds the current view from `S`. Horizontal row scroll positions are kept across re-renders.
- **Routing** uses the URL hash (`#/`, `#/l/<launcher>`, `#/d/<drive>`, `#/all`, `#/settings`). The setup page is not a route: it shows whenever there is no catalog.
- **Languages.** Every text goes through `t(key, vars)` (and `tn()` for plurals, using `Intl.PluralRules`); static markup carries `data-i18n` attributes. `www/lang/en.json` is loaded first, then the chosen language; a missing key falls back to English. Dates, sizes and durations use the browser's `Intl` formatting for that language.
- **Artwork resolution** happens on the client. `/api/games` returns the list of files in `data/covers`, and `artUrl(game, kind)` picks custom, then downloaded, then the scanner's local art. Cache-busting `?v=` stamps change after every upload or scan.
- **Untrusted text is never inserted as HTML.** Game names, paths and notes are set with `textContent` and `setAttribute`. The `html:` attribute of `h()` is used only for the app's own static SVG icons.
- **Theme.** Monochrome by design: black and grey surfaces, white primary actions. Colour comes only from the game art, and amber and red only mean warning and error. Design tokens are CSS custom properties at the top of `style.css`.
- **Controllers** (`gamepad.js`):
  - **Polling.** The script reads the browser's Gamepad API once per animation frame, and only while a controller is connected.
  - **Merged pads.** Every pad with the standard layout counts as one. A DualShock 4 that appears twice, as itself and as DS4Windows' virtual Xbox pad, therefore never acts twice.
  - **Spatial navigation.** The D-pad and left stick move focus to the nearest focusable element in that direction, using on-screen geometry. Left and right stay within the same row. Up and down go to the nearest row, then the closest card in it.
  - **Focus survives re-renders.** Focus is remembered by game id and row, so it lands back on the same card after a re-render.
  - **Ignored when not in front.** Input is dropped while the window isn't in front, and for 600 ms after it comes back.
  - **Controller mode styling.** `<html class="gp">` switches the page into controller mode: a visible focus ring, no mouse-hover effects, and a bar of button hints.
  - **On-screen keyboard.** View / Share opens it for the search box or the focused text field. It is drawn inside an open dialog when there is one (a modal dialog would cover anything outside it), and types by setting the field's value and firing an `input` event.

## Design decisions

| Decision | Why |
|---|---|
| Windows PowerShell 5.1, no modules | It's on every Windows 10/11 machine. Nothing to install, nothing to update. |
| PowerShell scripts are ASCII-only | PowerShell 5.1 reads BOM-less UTF-8 files as the ANSI code page, so non-ASCII characters in a `.ps1` silently break. Non-ASCII characters are built with `[char]0x…`. |
| No framework or build step in the web app | About 1,600 lines of JavaScript. A framework would outweigh the app and add a toolchain contributors must install. |
| Launch by catalog id only | A web page (even a malicious one) can never make the server run an arbitrary path or link. |
| Launcher links when available | Steam, Epic and Ubisoft handle updates, cloud saves, DRM and overlays when the game starts through them. |
| Exact-title artwork matching | A wrong cover is worse than none. Near matches are left for the user to pick in the Steam search. |
| User session instead of a Windows service | Services run in session 0 and can't show game windows on the user's desktop. |
| Never delete anything | Duplicate detection needs judgement. The hub shows sizes and folders, and you decide. |
| A game's processes = executables inside its install folder | Works for every launcher without knowing which executable a launcher will start, and needs no access to the game process itself. Anti-cheat software is never touched. |
| Minimize the hub instead of forcing focus onto the game | Windows deliberately limits which programs may grab the foreground. Minimizing the active window is always allowed and lets Windows hand focus to the game the normal way. |
| Controller input only while the hub is in front | A button pressed to quit a game must never launch something in the hub behind it. |
| `conhost --headless` instead of VBScript | VBScript is being removed from Windows. The console host's hidden mode runs PowerShell with no window and nothing extra to install. |
| The AI helper writes a prompt instead of calling an AI | No API keys, no account, no network call from Game Hub. People use the assistant they already have, and every folder it suggests is checked locally before it can be added. |
| Setup before the first scan | A drive that must stay private has to be excluded before anything reads it, so the first scan waits for the user. |
| DS4Windows rules through its own Auto Profiles | No driver, hook or process control of Game Hub's own: DS4Windows already knows how to switch per program. Game Hub only writes the rules it owns. |
| Controller facts looked up only on request, your answers first | The lookup sends game names, so it waits for a click. Wiki pages and store labels can be wrong or out of date, and nothing beats what the user saw in the game. |
| Machine translations, clearly labelled | 10 languages at once instead of waiting for volunteers, with a visible note and a one-click way to report mistakes. |
