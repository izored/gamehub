# HTTP API

The web app talks to `server.ps1` through this small JSON API. It's documented for contributors and for scripting your own tools, such as a Stream Deck button that launches a game. It's **not** a stable public API: endpoints may change between versions. Check the [changelog](../CHANGELOG.md).

Base URL: `http://localhost:8790` (or your `port`).

- [Rules for every request](#rules-for-every-request)
- [Read](#read) · [Games](#games) · [Artwork](#artwork) · [Library and settings](#library-and-settings)
- [Setup page](#setup-page) · [Backups](#backups) · [DS4Windows](#ds4windows)

## Rules for every request

- **Host.** Only `localhost:<port>` and `127.0.0.1:<port>` are answered. Anything else gets `403 Forbidden host`, which blocks DNS-rebinding attacks.
- **GET requests** need no headers.
- **POST requests:**
  - must send `X-GameHub: 1` (otherwise `403`);
  - are refused if they carry an `Origin` header other than `http://localhost:<port>` or `http://127.0.0.1:<port>` (`403`);
  - use a JSON body (`Content-Type: application/json`, at most 2 MB), except for the cover upload;
  - get `400 Invalid JSON body` if the body isn't valid JSON.
- **Errors** come back as `{ "error": "message", "code": "…", "arg": "…" }` with a matching status code. `code` and `arg` are present for known errors, so the page can show them in the chosen language: `unknownGame`, `exeNotFound`, `fileNotFound`, `folderNotFound`, `excludedDrive`, `scanRunning`, `nameEmpty`, `exePath`, `exeChoose`, `insideGame`, `schemeNotAllowed`, `locked`, `imageType`, `imageSize`, `ds4`, `unknownBackup`. Unexpected failures return `500` and are written to `logs\server.log`.
- **Optional lock.** With `lockToAccount` on, every `/api/…`, `/art/…`, `/covers/…` and `/export/…` request except `GET /api/status` also needs the `gh_key` cookie, otherwise `401` with code `locked`. The browser gets the cookie by opening `/?k=<key>`, where the key is in `data\session.key` (readable only by the Windows account running Game Hub); the server answers with the cookie and a redirect to `/`. Scripts can send the cookie themselves. See [SECURITY.md](../SECURITY.md#optional-lock-to-your-windows-account).

From PowerShell:

```powershell
$h = @{ 'X-GameHub' = '1' }
Invoke-RestMethod -Method Post http://localhost:8790/api/launch -Headers $h -ContentType 'application/json' -Body '{"id":"steam-2073850"}'
```

## Read

### `GET /api/games`

The catalog and everything the page needs to render it.

```json
{
  "catalog": { "generatedAt": "…", "games": [ … ], "drives": [ … ], "cleanup": [ … ], "skipped": [ … ], "newDays": 14, "excludedDrives": [] },
  "state":   { "favorites": ["epic-fortnite"], "launches": { "steam-2073850": "2026-11-21T19:13:53" } },
  "playtime": { "steam-2073850": { "minutes": 125, "sessions": 3, "last": "2026-11-22T23:10:00" } },
  "covers":  ["epic-fortnite-cover.jpg", "epic-fortnite-hero.jpg", "…"],
  "scanning": false,
  "extra": { "needsSetup": false, "notes": [], "language": "auto" }
}
```

- `catalog` is `null` until the first scan has finished. Field reference: [Configuration › Data files](configuration.md#data-files).
- `playtime` sums `data\sessions.jsonl` per game. Steam's own total is in each Steam game's `steamMinutes`; the page shows the larger of the two.
- `extra.needsSetup` is `true` while there is no game list: the page then shows the setup page. `extra.notes` lists files repaired from a backup at startup. `extra.language` is the `language` setting.

### `GET /api/status`

```json
{ "scanning": false, "generatedAt": "2026-11-21T21:07:06" }
```

`scanning` is `true` while a background job (scan or cover fetch) runs. This is the one endpoint the lock never blocks.

### `GET /api/settings`

```json
{
  "gameRoots": ["C:\\Games"], "excluded": ["H:"], "excludedLabels": ["BACKUP"],
  "drives": [{ "letter": "H:", "label": "BACKUP", "type": "fixed", "bus": "USB", "sizeBytes": 2000381014016, "freeBytes": 812345678848, "scanned": true, "excluded": true, "usb": true, "system": false }],
  "startup": true, "minimizeOnLaunch": true, "restoreAfterGame": true,
  "trackOutsideLaunches": false, "controllerSummon": true,
  "language": "auto", "lockToAccount": false, "otherAccounts": [],
  "backupCopyTo": "", "ds4windows": true,
  "hidden": [{ "id": "other-tool", "name": "Some Tool" }],
  "coverMisses": ["other-nocover"], "port": 8790, "root": "C:\\Users\\me\\AppData\\Local\\GameHub"
}
```

- `excluded` is the drive letters currently excluded: your letters, plus any drive whose label matches `excludedLabels`.
- `drives` describes every drive from Windows' own list; nothing is read on them. `bus` is the disk's connection (`USB`, `NVMe`, `SATA`...).
- `otherAccounts` lists the other enabled local Windows accounts; the page only offers the lock when there are some.
- `ds4windows` is `true` when DS4Windows is installed.

### `GET /export/my-games.csv`

Every game (duplicates left out) as a spreadsheet: name, launcher, drive, folder, how it starts, size in GB, play time in hours, last played, favorite. UTF-8 with a byte-order mark so Excel reads accents correctly.

### Static files

| Path | Serves |
|---|---|
| `/` | `www/index.html` |
| `/<file>` | `www/<file>` (letters, digits, `.`, `_`, `-` only) |
| `/lang/<file>` | `www/lang/<file>`: the [translations](translating.md) |
| `/brand/<file>` | `www/brand/<file>`: logo, icons, banner and `brand.css` ([brand assets](../www/brand/README.md)). Like `/<file>` and `/lang/`, it stays readable when the hub is locked to an account. |
| `/art/<file>` | `data/art/<file>` |
| `/covers/<file>` | `data/covers/<file>` |

Paths are resolved and checked to stay inside their folder.

## Games

### `POST /api/launch`

`{ "id": "<game id>" }` starts the game exactly as its catalog `launch` record says:

| Status | Meaning |
|---|---|
| `200` | `{ "ok": true, "launchedAt": "…" }`. The launch time is also recorded in `state.json`. |
| `404` | Unknown id. |
| `410` | The executable no longer exists. Rescan, or fix it with the pen. |
| `400` | The launch link uses a scheme outside the allowlist. |

Only ids from the catalog can be launched. The server never takes a path or link from the request. Xbox app links (`shell:AppsFolder\…`) are started through Windows Explorer.

After a successful launch, the server starts `watch-game.ps1` for that game. The watcher records the play session, and (per `minimizeOnLaunch` and `restoreAfterGame`) minimizes the Game Hub window once the game's window opens and restores it when the game has closed. See [Architecture › The launch watcher](architecture.md#the-launch-watcher-watch-gameps1). This happens in the background: the response doesn't wait for it.

### `POST /api/favorite`

`{ "id": "<game id>", "value": true | false }` stars or unstars a game. Returns the new state: `{ "favorites": [...], "launches": {...} }`.

### `POST /api/open-folder`

`{ "id": "<game id>" }` or `{ "path": "<folder>" }` opens a folder in Explorer. A `path` is accepted only if it's exactly a game's install folder or a cleanup item's path.

### `POST /api/game/save`

Edits a game. All fields except `id` are optional:

| Field | Effect |
|---|---|
| `name` | New display name. It can't be empty. |
| `exe` | Full path to an `.exe`. It must exist and must not be on an excluded drive. The game then starts this file directly. Starts a background rescan to refresh the icon. |
| `args` | Launch arguments, used when the game starts from its executable. |
| `resetExe: true` | Removes the custom executable and arguments, then rescans. |
| `hidden: true` | Hides the game. A game you added by hand is removed instead. |
| `ds4` | `"on"`, `"off"` or `"profile:<name>"`: what DS4Windows does while the game runs. When it changes, the DS4Windows rules are rewritten at once (see [DS4Windows](#ds4windows)). |

Returns `{ "ok": true, "rescanning": <bool>, "ds4": { "written", "restarted", "running" } | null }`. Changes are stored in `overrides.json`.

### `POST /api/game/add`

`{ "name": "...", "exe": "C:\\...\\Game.exe", "args": "..." }` adds a game by hand.

| Status | Meaning |
|---|---|
| `200` | `{ "ok": true, "id": "manual-…" }`. A background rescan follows. |
| `400` | No name; or the path isn't a full path to an existing `.exe`; or it's on an excluded drive. |
| `409` | The executable is inside another game's folder. Edit that game instead. |

### `POST /api/game/unhide`

`{ "id": "<game id>" }` shows a hidden game again. A background rescan follows.

## Artwork

### `POST /api/cover/upload?id=<game id>&kind=cover|hero`

The body is the **raw image bytes**, not JSON: JPEG, PNG or WebP, up to 25 MB. The type is checked from the file's first bytes. It's saved as `data/covers/<id>-<kind>.custom.<ext>`.

| Status | Meaning |
|---|---|
| `200` | `{ "ok": true, "file": "…" }` |
| `400` | Bad `kind`. |
| `404` | Unknown game. |
| `413` | Larger than 25 MB. |
| `415` | Not JPEG, PNG or WebP. |

### `POST /api/cover/reset`

`{ "id": "<game id>", "kind": "cover" | "hero" }` deletes the custom image.

### `POST /api/steam/search`

`{ "q": "search text" }` returns `{ "items": [{ "appid": 2073850, "name": "THE FINALS", "thumb": "https://…" }] }`, with at most 12 apps. A query shorter than 2 characters returns an empty list.

### `POST /api/cover/steam`

`{ "id": "<game id>", "appid": 2073850 }` downloads that Steam app's cover, hero and logo for the game, removes its custom cover and background, and saves `steamAppId` in `overrides.json`. It returns `502` if Steam has no cover for that app.

### `POST /api/covers/fetch`

`{ "force": false }` runs `fetch-covers.ps1` as the background job. `force: true` retries earlier misses and re-downloads all artwork. It returns `202`, or `409` if a job is already running.

## Library and settings

### `POST /api/rescan`

Runs `scan-games.ps1` (scan plus cover fetch) as the background job. It returns `202 { "ok": true, "scanning": true }`, or `409` if a job is already running. Poll `GET /api/status` until `scanning` is `false`.

### `POST /api/settings`

Every field is optional:

| Field | Effect |
|---|---|
| `gameRoots` | Replaces the list of game folders and starts a rescan. A folder that's already saved is kept as-is, even if its drive is disconnected. A new folder must exist and must not be on an excluded drive, otherwise the request fails with `400` and nothing is saved. |
| `excludeDriveLetters` | Replaces the never-read drive letters (`["H:", "E"]`) and starts a rescan. |
| `startup` | Creates or removes the Startup-folder shortcut. |
| `minimizeOnLaunch`, `restoreAfterGame` | Apply from the next launch. |
| `trackOutsideLaunches` | Starts the outside-launch tracker when turned on; it stops by itself when turned off. |
| `controllerSummon` | Starts the controller helper when turned on; it stops by itself within 30 seconds when turned off. |
| `language` | `auto` or a language code from `www/lang/index.json`. |
| `lockToAccount` | Turning it on creates `data\session.key` in the data folder and sets the lock cookie on this response. If the key cannot be created, the setting goes back to off and the request fails with `500`. |
| `backupCopyTo` | A folder for copies of every new backup, or `""` for none. It must exist and must not be on an excluded drive. |
| `pads` | `{ "ds4": "bt", "dualsense": "usb" }`: how you connect each PlayStation controller (`bt`, `usb`, `none`, or `""` to follow what Windows shows). Only the models you send change. |

It returns `{ "ok": true, "rescanning": <bool>, "startup", "minimizeOnLaunch", "restoreAfterGame", "trackOutsideLaunches", "controllerSummon", "language", "lockToAccount", "backupCopyTo" }`.

### `POST /api/pick`

`{ "kind": "exe" | "folder", "initial": "<path>" }` opens the native Windows file or folder dialog on the user's desktop, in front of the browser. It waits for the user to choose, then returns `{ "path": "C:\\..." }`, or `{ "path": null }` if cancelled. The server handles one request at a time, so other requests wait while the dialog is open.

## Setup page

### `GET /api/setup/drives`

`{ "drives": [ … ] }`, the same drive descriptions as in `GET /api/settings`. Nothing is read on the drives.

### `POST /api/setup/folders`

`{ "exclude": ["H:"] }` returns the launcher folders and suggested game folders on the drives that are not excluded:

```json
{
  "launchers": [{ "launcher": "Steam", "path": "C:\\Program Files (x86)\\Steam\\steamapps\\common", "covered": true }],
  "suggestions": [{ "path": "C:\\Games", "current": true }, { "path": "C:\\Program Files\\Epic Games", "current": false }]
}
```

`launchers` only lists folders whose games are all found through the launcher itself (Steam libraries, the Xbox app's `XboxGames`). The folders of the other launchers are in `suggestions`, because scanning them also finds games the launcher has forgotten. Other suggestions are top-level folders named like a game folder.

### `POST /api/setup/check`

`{ "paths": ["D:\\Games", "H:\\Games"], "exclude": ["H:"] }` checks each path and returns `{ "results": [{ "path", "status", "launcher" }] }`, one per path, in order. `exclude` defaults to the saved never-read drives.

| `status` | Meaning |
|---|---|
| `ok` | Can be added. |
| `missing` | The folder doesn't exist. |
| `excluded` | On a never-read drive (checked before anything is read there). |
| `launcher` | Inside a folder Steam or the Xbox app fully covers; `launcher` names it. |
| `nested` | Inside another `ok` folder of the same list; `launcher` holds that folder. |
| `duplicate` | Listed twice. |
| `tooBroad` | The Windows drive's root, `Windows`, `Program Files`, `ProgramData`, `Users` or your user folder. |
| `invalid` | Not a full folder path. |

### `POST /api/setup/finish`

`{ "exclude": [...], "gameRoots": [...], "startup", "minimizeOnLaunch", "restoreAfterGame", "lockToAccount", "language" }` saves the setup page's choices (only `ok` folders are kept), creates or removes the Startup shortcut when `startup` is given, and starts the first scan. It returns `202 { "ok": true, "scanning": true, "gameRoots": [...] }`.

## Backups

### `GET /api/backups`

`{ "backups": [{ "name": "gamehub-2026-11-23_022528.zip", "created": "…", "sizeBytes": 6144, "reason": "daily" | "manual" | "before restore" }], "copyTo": "" }`, newest first.

### `POST /api/backups/create`

Makes a backup now, even if nothing changed. Returns `{ "ok": true, "name": "…" }`.

### `POST /api/backups/restore`

`{ "name": "gamehub-….zip" }` backs up the current state, then puts back the files from that backup (only Game Hub's own files: `config.json`, `overrides.json`, files in `data\` and custom covers) and reloads the settings. Returns `{ "ok": true, "restored": ["config.json", "…"] }`, or `500` with code `unknownBackup`.

## DS4Windows

### `GET /api/ds4windows`

```json
{
  "found": true, "running": true, "controls": true, "exe": "C:\\…\\DS4Windows.exe", "profiles": ["Default"],
  "games": { "epic-fortnite": "off" },
  "wraps": { "ds4": true, "dualsense": true }, "hides": false,
  "pads": [ { "model": "ds4", "link": "bt", "how": "now", "found": "bt" },
            { "model": "dualsense", "link": "usb", "how": "set", "found": "none" } ],
  "facts": { "epic-fortnite": { "checkedAt": "2026-11-23T19:37:06",
             "pcgw": { "page": "Fortnite", "ps": "yes", "models": ["ds4", "dualsense"], "usb": true, "bt": ["dualsense"], "btListed": true, "note": "…" },
             "steam": null, "files": [] },
             "steam-2073850": { "…": "…", "steamInput": "on" } },
  "checkedAt": "2026-11-23T19:37:06", "progress": null, "checking": false,
  "feedback": { "epic-fortnite": { "answer": "fine", "rule": "off", "at": "2026-11-23T20:14:20" } }
}
```

- `games` holds only the games with a rule.
- `controls` is `false` when `ds4windowsFolder` points to a folder the running DS4Windows doesn't use; `running` is then `false` too, and Game Hub never restarts DS4Windows.
- `wraps`: which controllers DS4Windows takes over (its *Device Options*). `hides`: its *Hide DS4 Controller* setting.
- `pads`: one entry per PlayStation model. `link` is `bt`, `usb` or `none`; `how` says where it comes from (`now` connected, `paired` over Bluetooth, `seen` before, `set` in Settings, `missing`); `found` is what Windows shows.
- `facts`: what [Check my games](controllers.md#which-games-need-ds4windows) found per game (`data\controller-support.json`): PCGamingWiki's PlayStation fields (`ps` is `yes`, `no` or `unknown`; `usb` and `bt` are `null` when the wiki doesn't say), Steam's labels (`ds4`, `dualsense`, `full`, `partial`), and Sony controller files in the game folder. Steam games add `steamInput` (`on`, `off` or `default`), read from Steam's own settings at each request.
- `progress` is `{ "done", "total" }` while a check runs.
- `feedback`: your answers (`data\controller-feedback.json`). The page turns all of this into suggestions with `www/pad-advice.js`.

### `POST /api/ds4windows/check`

`{ "force": false }` starts `check-controllers.ps1` in the background, separately from scans, one at a time. Without `force`, games checked in the last 30 days are skipped. Returns `202 { "ok": true, "checking": true }`; follow it with `GET /api/ds4windows`.

### `POST /api/ds4windows/feedback`

`{ "id": "<game id>", "answer": "fine" | "double" | "none" | "skip" | "clear", "rule": "on" | "off" }` records how the controller worked. `rule` says whether DS4Windows was on or off; without it, it is the game's current rule, or `off` when DS4Windows isn't running. `skip` means *I didn't use a controller*, `clear` forgets the answer. Returns `{ "ok": true, "feedback": { … } }`, `400` for another answer, `404` for an unknown game.

### `POST /api/ds4windows`

`{ "games": { "<game id>": "on" | "off" | "profile:<name>" } }` saves the choices to `overrides.json`, rewrites DS4Windows' `Auto Profiles.xml` (only the rules Game Hub wrote; the previous file is copied to `data\backups`), and restarts DS4Windows if it is running, because it reads its rules only at startup. Returns `{ "ok": true, "written": <rules>, "restarted": <bool>, "running": <bool> }`, or `500` with code `ds4` when DS4Windows isn't installed. See [Controllers › DS4Windows rules per game](controllers.md#ds4windows-rules-per-game).
