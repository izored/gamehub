# Contributing to Game Hub

Thanks for helping. Bug reports, launcher support, better game detection and UI polish are all welcome.

- [Ground rules](#ground-rules)
- [Development setup](#development-setup)
- [Before you open a pull request](#before-you-open-a-pull-request)
- [Adding a launcher](#adding-a-launcher)
- [Adding or changing text](#adding-or-changing-text)
- [Reporting bugs](#reporting-bugs)
- [Releasing](#releasing)

## Ground rules

The project stays small and dependency-free on purpose. Please keep it that way.

1. **No build step and no dependencies.** No npm packages, PowerShell modules or binaries. Everything must run on a clean Windows 10/11 install.
2. **Windows PowerShell 5.1 compatible.** The scripts run under `powershell.exe`, not PowerShell 7, so avoid:
   - `??`, `?.`, the ternary operator and `&&`/`||` pipeline chains;
   - `ForEach-Object -Parallel`;
   - `ConvertFrom-Json -AsHashtable` and `-Depth`;
   - any other 6.0+ feature.
3. **PowerShell files are ASCII only.** PowerShell 5.1 reads BOM-less UTF-8 as the ANSI code page, so a single `é`, `—` or `™` in a `.ps1` can break parsing or corrupt strings. Build such characters with `[char]0x2122` instead. Web files (`www/`) and docs are UTF-8 and may use any character.
4. **Vanilla JavaScript.** No framework, no transpiler. Target current Chromium and Firefox. Never put game data into `innerHTML`: use `textContent` or the `h()` helper, whose `html:` attribute is reserved for the app's own static icons.
5. **Monochrome UI.** Use black and grey surfaces and white primary actions. Colour comes from game art only; amber and red are reserved for warnings and errors. Reuse the CSS custom properties at the top of `style.css`.
6. **Safety first.**
   - The server must never launch a path or link that came from a request.
   - It must never read excluded drives, not even to list them on the setup page.
   - It must never delete user files.
   - Background helpers may read window titles, executable paths and controller state, and may only move the Game Hub window.
7. **Privacy.**
   - No telemetry.
   - Network calls only for artwork and for the controller check (only when the user presses *Check my games*), sending only titles or store ids.
   - Never call an AI service, or any other service, from Game Hub. The AI folder helper only writes a prompt the user copies themselves.
   - Your own `config.json`, `overrides.json`, `data/` and `logs/` live in `%LOCALAPPDATA%\GameHub`, outside the repository. Never copy anything from them into a commit: no paths, drive names or game lists. The pre-commit hook checks for exactly that.

## Development setup

1. Fork and clone the repository anywhere, then turn on the pre-commit hook. It runs `tools\check-release.ps1 -Staged` (the checks below plus a privacy scan) before every commit:

   ```powershell
   git config core.hooksPath .githooks
   ```

   Put an empty `portable.txt` next to `server.ps1`. That keeps this copy's data in the repository folder (`.gitignore`d), instead of sharing `%LOCALAPPDATA%\GameHub` with your everyday hub.
2. Run the server in the foreground to see errors:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
   ```

3. Open `http://localhost:8790/`.

To keep your everyday hub running alongside a development copy, give the copy another `port` in its own `config.json` (with `portable.txt`, next to the scripts). Each port gets its own single-instance lock.

- **Web files** (`www/`) are served from disk on every request. Edit, then reload the page.
- **`server.ps1`** changes need a server restart.
- **`scan-games.ps1` / `fetch-covers.ps1`** run in a new process each time, from **Settings › Rescan now** or the command line. Add `-NoCovers` to skip downloads while you work on detection.
- **The setup page** shows whenever `data\games.json` is missing: rename it in your development copy to work on it. `POST /api/setup/finish` with `startup` creates or removes the **real** Startup shortcut (it is per Windows account, not per copy), so leave that switch alone in a development copy.
- **`controller-helper.ps1`** is started by every server copy whose `controllerSummon` is on, but only one runs per account. Set `controllerSummon` to `false` in a development copy.
- **DS4Windows.** A development copy finds your real DS4Windows. Set `ds4windowsFolder` in its `config.json` to a scratch folder holding a copy of DS4Windows' `Profiles.xml`: *Apply to DS4Windows* then writes there, and your DS4Windows is never restarted.
- **Start the server from `powershell.exe`.** Started from PowerShell 7 (`pwsh`), Windows PowerShell inherits PowerShell 7's module path; the server cleans it at startup, but your own test scripts may hit the same problem (*module could not be loaded*).

Every script accepts `-Root <folder>` to run against another Game Hub folder.

## Before you open a pull request

Run these from the repository root. `tools\check-release.ps1` runs steps 1 to 4 in one go, plus the privacy scan; the pre-commit hook runs it on what you stage.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-release.ps1
```

Or one at a time:

**1. Parse every script with Windows PowerShell 5.1:**

```powershell
powershell -NoProfile -Command "Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { `$e = `$null; [void][Management.Automation.Language.Parser]::ParseFile(`$_.FullName, [ref]`$null, [ref]`$e); if (`$e) { `$_.Name; `$e } }"
```

**2. Check that the PowerShell and VBScript files are ASCII only:**

```powershell
Get-ChildItem -Recurse -Include *.ps1, *.vbs | Where-Object { [IO.File]::ReadAllBytes($_.FullName) -gt 127 } | Select-Object FullName
```

**3. Check the JavaScript syntax,** if you have Node.js:

```powershell
node --check www/app.js
node --check www/gamepad.js
node --check www/pad-advice.js
node tools/test-pad-advice.js
```

**4. Check the translations** whenever you add or change text in the page:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-translations.ps1
```

**5. Test by hand what you touched:**

- **Scan.** Rescan, and check that no game disappeared or changed name unexpectedly. Compare `data/games.json` before and after.
- **Launch.** Launch one game for each launcher type you touched. With the *While you play* options on, Game Hub must minimize once the game's window opens, and come back a few seconds after you quit. `logs\watch.log` shows each step, and the session must appear in `data\sessions.jsonl`.
- **Controller.** If you touched `gamepad.js`, the markup or the layout, go through Home, a launcher tab, Settings, the setup page and the edit dialog with a controller, and type a search with the on-screen keyboard. Check that a button held while Game Hub comes back doesn't trigger anything.
- **Edit.** Edit a game (name, executable, cover upload), add a game, hide and unhide one.
- **First run.** Do this on a copy with another port, without `config.json` and `data/`. The setup page must appear, scan nothing until *Scan my games*, then show the library.
- **Backups.** If you touched `lib/backup.ps1` or what is stored in `data\`, make a backup, damage a file (empty it), restart: it must be repaired and the banner shown. Restore a backup and check that a *before restore* backup was made first.
- **Languages.** Switch the page to a language with long words (German) and one without spaces (Japanese) and look for cut-off buttons.
- **Security.** If you changed the request handling, check that a POST without `X-GameHub: 1`, or with a foreign `Origin`, gets `403`. With `lockToAccount` on, a request without the cookie must get `401`.

**6. Update the docs** if behaviour or configuration changed, and add a line under **[Unreleased]** in `CHANGELOG.md`.

Keep pull requests focused: one fix or feature each. In the description, explain the why, and say how you tested it.

## Adding a launcher

1. **Detection.** In `scan-games.ps1`, add a section next to the other launchers (Steam, Epic, Ubisoft, GOG, Battle.net, Riot, Amazon, Rockstar, Xbox app) that reads the launcher's own install records (manifests, registry, database). For each install, call `Add-Game` with:
   - `-Source` and `-IdBase`: a **stable** id, preferably the launcher's own game id rather than a folder name;
   - `-Name`, `-Dir` and `-Exe`;
   - `-LaunchUri`, if the launcher has a link scheme, or `-LaunchExe` and `-LaunchArgs` when the game starts through a launcher program with arguments (as the Riot Client does).

   Launcher sections run before folder scanning, so they claim their folders first.
2. **Launching.** If the launcher has a URI scheme, add it to `$uriSchemes` in `server.ps1`. Otherwise games start from `-Exe`.
3. **UI.** Add the source key to `SOURCES`, `SHORT` and `VIA` at the top of `www/app.js` (brand names, not translated).
4. **Setup page.** If the launcher has its own install folder, add it to `Get-LauncherRoots` in `lib/setup.ps1`: `covered` only when every game in that folder is always found through the launcher.
5. **Play time.** Nothing to do if the game's programs run from its install folder; the watcher and the tracker find them there.
6. **Artwork.** If the launcher keeps key art locally, the way Epic's catalog cache does, add a source to `lib/store-art.ps1` and call it from `fetch-covers.ps1`.
7. **Docs.** Add the launcher to `docs/launchers.md`, the table in `README.md`, the launcher list in the bug report form, and the changelog.

## Adding or changing text

Every text the page shows lives in `www/lang/en.json` and is looked up with `t('key')` in the scripts or `data-i18n="key"` in `index.html`.

1. Add the English text to `en.json` under a key named after where it appears (`settings.…`, `toast.…`, `err.…`). Use `{name}`-style placeholders, never string concatenation, and `.one` / `.other` keys with `tn()` for anything with a number.
2. Use the key in the page.
3. Leave the other languages alone, or add your own language's text if you speak it: missing keys fall back to English, and translators fill them in later.
4. Run `tools\check-translations.ps1`.

Error messages from the server are matched to a code in `$errPatterns` in `server.ps1`, so the page can translate them (`err.<code>`). Add a pattern when you add an error users will see. See [Translating](docs/translating.md) for the translators' side.

## Reporting bugs

Open an issue with the bug template. Include:

- your Windows version;
- the launcher involved;
- what you expected and what happened;
- the relevant lines from `logs/server.log` or `logs/scan.log`.

Logs and `games.json` contain folder paths and game names, so remove anything you consider private before posting.

Security problems: please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Releasing

The release page is the changelog. The version's section of `CHANGELOG.md` becomes the release notes word for word, with the zip's SHA-256 added under the heading. So write it for the people who will read the release page:

- one bullet per change: a unique emoji, a **bold sentence that says what is now true**, then plain words on what was wrong or what it brings;
- full `https://github.com/izored/gamehub/blob/main/...` links: a release page can't follow links relative to the repository, and `make-release.ps1` refuses them;
- when you point at a script people will run, link the release's own copy (`https://github.com/izored/gamehub/blob/vx.y.z/...`), so they read exactly what is in the zip, and say in plain words what it does;
- technical details (API, configuration) inside a `<details>` block at the end.

Then:

1. Rename `## [Unreleased]` to `## [x.y.z] - <date>`, add an empty `## [Unreleased]` above it, and update the links at the bottom of the changelog.
2. Set `version` in `www/brand/about.json` to the same number. **Settings › Made by** shows it.
3. Preview the notes: `powershell -ExecutionPolicy Bypass -File tools\make-release.ps1 -Version x.y.z -Title "<one-line headline>" -NotesOnly` writes `dist\notes-x.y.z.md`.
4. Commit and push.
5. Run the same command with `-Publish` instead of `-NotesOnly`. It checks the tree is committed and pushed, runs `tools\check-release.ps1`, builds `dist\GameHub-x.y.z.zip` with `git archive`, and creates the release **Game Hub vx.y.z — headline** with the zip and its checksum.

## Code of conduct

Be kind and constructive. Assume good intent, and focus on the code, not the person.
