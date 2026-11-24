# Configuration

Game Hub has two settings files, both in your [data folder](installation.md#where-your-data-lives) (`%LOCALAPPDATA%\GameHub`) and both optional to edit by hand:

| File | What it's for | Created |
|---|---|---|
| [`config.json`](#configjson) | Machine-level settings: port, language, which drives and folders to scan, what the hub does while you play, controller, lock and backup options | Copied from `config.example.json` on first run, then filled in by the [setup page](usage.md#the-setup-page) |
| [`overrides.json`](#overridesjson) | Per-game fixes: names, executables, artwork, hidden games, duplicates, manual additions | When you first edit a game in the hub, or by hand from `overrides.example.json` |

Neither file is committed to git. Both describe your machine and library.

The rest of this page covers [identifying games (ids)](#game-ids), the [data files](#data-files) the hub writes, and the [logs](#logs).

> **Editing by hand while the server runs.** The server reads `config.json` once at startup. When you change a setting in **Settings** (or finish the setup page), it writes its in-memory copy back to the file, which would undo edits you made by hand in the meantime. Restart the server after editing `config.json`.
>
> `overrides.json` is read fresh on every request, so editing it while the server runs is safe. The hub rewrites it when you edit a game in the UI. Your content is kept, but formatting is not.

## config.json

```json
{
  "port": 8790,
  "language": "auto",
  "excludeDriveLetters": ["H:"],
  "excludeVolumeLabels": ["BACKUP"],
  "gameRoots": ["C:\\Games", "D:\\Games", "E:\\"],
  "discoverRoots": ["C:\\Program Files", "C:\\Program Files (x86)"],
  "ignore": ["C:\\Program Files\\Epic Games\\Launcher", "E:\\Downloads"],
  "newDays": 14,
  "minimizeOnLaunch": true,
  "restoreAfterGame": true,
  "trackOutsideLaunches": false,
  "controllerSummon": true,
  "lockToAccount": false,
  "backupCopyTo": ""
}
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `port` | number | `8790` | Port of the local server. The page is served at `http://localhost:<port>/`. Restart the server after changing it. |
| `language` | string | `auto` | Language of the page: `auto` (follow the browser) or `en`, `fr`, `es`, `pt-BR`, `de`, `ru`, `zh-Hans`, `ja`, `ko`, `pl`, `tr`. Also in **Settings › Language**. See [Translating](translating.md). |
| `excludeDriveLetters` | string[] | `[]` | Drives that are never read, written as `"H:"` (letter plus colon, any case). Set by the setup page and **Settings › Drives**. |
| `excludeVolumeLabels` | string[] | `[]` | Drives that are never read, by volume label (any case). Use this for a removable drive that may get a different letter each time. |
| `gameRoots` | string[] | set by the setup page | **Game folders.** Every immediate sub-folder is treated as one game. Its executable is picked automatically. Drive roots such as `"E:\\"` are allowed. Folders that don't exist are skipped. Also editable in **Settings › Game folders**. |
| `discoverRoots` | string[] | Program Files, Program Files (x86) | **Discovery folders.** A sub-folder counts as a game here only if it contains game-engine files, and it isn't a known non-game vendor folder (Microsoft, NVIDIA, Adobe, launchers…). |
| `ignore` | string[] | Epic launcher folder | Full paths skipped by the folder scan and discovery, including everything inside them. They don't affect games found through a launcher (Steam, Epic, Ubisoft, GOG, Battle.net, Riot, Amazon, Rockstar, Xbox app). To drop one of those, hide it instead. |
| `newDays` | number | `14` | How many days a newly installed game counts as new: the **NEW** badge and the billboard's *New on your PC*. |
| `minimizeOnLaunch` | boolean | `true` | Minimize the Game Hub window as soon as the game you launched opens its window, so the keyboard, mouse and controller go straight to the game. Also in **Settings › While you play**. See [Using Game Hub](usage.md#while-you-play). |
| `restoreAfterGame` | boolean | `true` | Bring Game Hub back to the front when the game has fully closed. Also in **Settings › While you play**. |
| `trackOutsideLaunches` | boolean | `false` | Also count the [play time](usage.md#play-time) of games started outside Game Hub (`track-games.ps1` checks once a minute). Also in **Settings › While you play**. |
| `controllerSummon` | boolean | `true` | Hold View + Menu on a controller for 1.5 seconds to bring Game Hub back (`controller-helper.ps1`). Also in **Settings › Controllers**. See [Controllers](controllers.md#bring-game-hub-back-with-the-controller). |
| `lockToAccount` | boolean | `false` | Only the Windows account that runs Game Hub can use it. Also in **Settings › Security**, shown when the PC has other accounts. See [SECURITY.md](../SECURITY.md#optional-lock-to-your-windows-account). |
| `backupCopyTo` | string | `""` | A second folder that receives a copy of every new [backup](usage.md#backups). Must exist and not be on a never-read drive. Also in **Settings › Backups**. |
| `pads` | object | none | How you connect each PlayStation controller, for the [DS4Windows suggestions](controllers.md#which-games-need-ds4windows): `{ "ds4": "bt", "dualsense": "usb" }`, with `bt`, `usb` or `none`. A missing model follows what Windows shows. Set in **Settings › Controllers**. |
| `ds4windowsFolder` | string | none | DS4Windows' settings folder (the one with `Profiles.xml`), only needed when Game Hub can't find it. If it isn't the folder the running DS4Windows uses, Game Hub writes its rules there but never restarts DS4Windows, which keeps a development copy away from your real DS4Windows. |

A missing key takes its default, so a `config.json` from an older version keeps working without editing.

**Which drives are read at all.** Only fixed local disks are scanned. Removable, network and optical drives are always skipped. Some USB SSDs report themselves as fixed disks; exclude those with `excludeDriveLetters` or `excludeVolumeLabels`. The setup page ticks every USB drive for you.

On excluded drives:

- the scanner reads nothing;
- the hub refuses executables and game folders located there;
- launcher libraries stored there (a Steam library, for example) are ignored.

**Game folders vs discovery.**

| | Game folders (`gameRoots`) | Discovery (`discoverRoots`) |
|---|---|---|
| What counts as a game | Every sub-folder | Only sub-folders that contain engine files |
| Suits | A folder that holds only games, like `D:\Games` | Shared folders such as Program Files |

Discovery also checks the install folder of every program in the Windows uninstall list, using the same rule.

## overrides.json

Fixes the scanner can't know about. They're applied on every scan, so they survive rescans.

```json
{
  "games": {
    "other-somegame":   { "name": "Some Game: Definitive Edition", "exe": "bin\\SomeGame.exe", "args": "-windowed" },
    "epic-rocketleague": { "steamAppId": 252950 },
    "other-minecraft-bedrock-edition": { "msStoreId": "9NBLGGH2JHXJ" },
    "other-tool":       { "hidden": true, "name": "Some Tool" },
    "steam-1234560":    { "duplicateOf": "other-somegame", "note": "Steam copy never launched; keep the D: copy." }
  },
  "add": [
    { "name": "Retro Game", "dir": "D:\\Emulators\\RetroGame", "exe": "RetroGame.exe", "args": "--fullscreen" }
  ],
  "cleanup": [
    { "path": "C:\\Downloads\\OldInstaller", "title": "Installer archive", "keep": "D:\\Games\\SomeGame", "note": "Already installed." }
  ]
}
```

A complete example is in [`overrides.example.json`](../overrides.example.json).

### `games.<id>`

Keys are [game ids](#game-ids). Each value can hold any of these fields:

| Field | Type | Set by the UI | Meaning |
|---|---|---|---|
| `name` | string | Edit › Name | Display name. |
| `exe` | string | Edit › Executable | Executable to start, either absolute or relative to the install folder. The hub then starts this file directly, even for Steam, Epic or Ubisoft games. |
| `args` | string | Edit › Launch arguments | Arguments for the executable. Ignored when the game starts through a launcher link. |
| `uri` | string | | Launch through this link instead. It must start with `steam://`, `uplay://`, `com.epicgames.launcher://`, `origin2://`, `battlenet://` or `amazon-games://`, or be an Xbox app entry `shell:AppsFolder\<package>!<app>`; anything else is refused at launch time. It wins over `exe`. |
| `hidden` | boolean | Edit › Hide from hub | Leaves the game out of the hub. Its folder stays claimed, so it isn't picked up again under another name. |
| `warning` | string | | Text shown as ⚠ on the card and in the edit dialog. It replaces the scanner's own warning. |
| `note` | string | | Explanation shown in the Cleanup panel, for duplicates. |
| `duplicateOf` | id | | Marks this install as a second copy of the game with that id. It's removed from rows, search and counts, and listed under **Cleanup** with the copy to keep. |
| `steamAppId` | number | Edit › Search Steam artwork | Steam app whose artwork to use. Useful when the title differs between stores. |
| `msStoreId` | string | | Microsoft Store product id, the 12-character code in the Store URL (for example `9NBLGGH2JHXJ`), to take artwork from the Microsoft Store. Setting it also skips the Steam title search for this game. |
| `noArt` | boolean | | Never download artwork for this game. |
| `ds4` | string | Edit › DS4Windows, Settings › Controllers | What DS4Windows does while the game runs: `off`, or `profile:<name>`. Missing means *keep DS4Windows on*. See [Controllers](controllers.md#ds4windows-rules-per-game). |

### `add[]`

Games the scanner misses, for example a folder outside every game folder. Games added through **Settings › Add a game** are stored here too.

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | Display name. |
| `dir` | yes | Install folder. It must exist and must not be on an excluded drive. |
| `exe` | no | Executable, absolute or relative to `dir`. If you leave it out, it's picked the same way as for scanned games. |
| `args` | no | Launch arguments. |
| `uri` | no | Launcher link, with the same allowed schemes as above. |
| `id` | no | Fixed id. Default: `manual-<name-slug>`. |
| `source` | no | `steam`, `epic`, `ea`, `ubisoft`, `gog`, `battlenet`, `riot`, `amazon`, `rockstar`, `xbox` or `other` (default). It decides which row and tab the game appears in. Other values only show up in *All games* and search. |

A folder already claimed by a scanned game can't be added a second time. To change that game, edit it instead.

### `cleanup[]`

Leftovers the scanner can't recognise, listed in the **Cleanup** panel. The hub only displays them, with their size, and never deletes anything.

| Field | Required | Meaning |
|---|---|---|
| `path` | yes | A folder. Listed only while it exists and is not on an excluded drive. |
| `title` | yes | Short label. |
| `keep` | no | The copy to keep, shown as *Keep: …*. |
| `note` | no | Why it can go. |

## Game ids

Every game has a stable id, used by `overrides.json`, favorites and play history:

| Source | Id |
|---|---|
| Steam | `steam-<appid>` |
| Epic (launcher or `.egstore` folder) | `epic-<install-folder-name>` |
| Ubisoft Connect | `ubi-<ubisoft install id>` |
| EA | `ea-<install-folder-name>` |
| GOG Galaxy | `gog-<GOG game id>` |
| Battle.net | `bnet-<Blizzard uninstall id>` |
| Riot Client | `riot-<product>` (for example `riot-valorant`) |
| Amazon Games | `amazon-<name>` |
| Rockstar Games Launcher | `rockstar-<name>` |
| Xbox app | `xbox-<name>` |
| Anything else found by the scan | `other-<install-folder-name>` |
| Added by hand | `manual-<name>` |

Names are lower-cased with every run of other characters replaced by `-`. A clash gets a `-2`, `-3`… suffix. **Renaming or moving a game's folder changes its id** for Epic, EA, standalone and manually added games, so update its overrides and star it again.

To list the ids:

```powershell
(Get-Content "$env:LOCALAPPDATA\GameHub\data\games.json" -Raw | ConvertFrom-Json).games | Select-Object id, name, source, installDir
```

## Data files

Everything under `data\` (in the data folder) is generated. Deleting it resets the hub's library, favorites, play time, backups and downloaded artwork, but not your settings. The setup page appears on the next start.

| Path | Written by | Content |
|---|---|---|
| `data\games.json` | scanner (and the server when you edit) | The catalog, described below. |
| `data\state.json` | server | `favorites`: ids in the order you starred them. `launches`: `{ id: last launch time }`. |
| `data\art\` | scanner | `<id>.png`, the icon extracted from the executable. `<id>-header/cover/hero/logo.*`, images copied from Steam's local library cache. |
| `data\covers\` | cover fetcher, uploads | `<id>-cover/hero/logo.<ext>` for downloaded artwork, `<id>-<kind>.custom.<ext>` for your uploads, and `_misses.json` for games no store had art for. |
| `data\sessions.jsonl` | launch watcher, tracker | One play session per line: `{ id, start, end, minutes, by }`, where `by` is `hub` or `tracker`. |
| `data\game-windows.json` | launch watcher | `{ id: { exe, title, seen } }`: each game's main window, used for the DS4Windows title rules. |
| `data\backups\` | server | `gamehub-<date>_<time>.zip` [backups](usage.md#backups), `last-backup.txt` (what the last backup contained), and `ds4windows-auto-profiles-<date>.xml` copies of DS4Windows' rules file before Game Hub changed it. |
| `data\ds4windows-managed.json` | server | The DS4Windows rules Game Hub wrote, so it only ever replaces its own. |
| `data\controller-support.json` | `check-controllers.ps1` | What **Check my games** found for each game: PCGamingWiki's PlayStation fields, Steam's controller labels, Sony controller files in the game folder. Safe to delete; press **Check my games** again. |
| `data\controller-feedback.json` | server | Your answers about how the controller worked in each game (`{ id: { answer, rule, at } }`). Included in backups. |
| `data\controllers-seen.json` | server | When each PlayStation controller was last seen connected, by USB or Bluetooth. |
| `data\session.key` | server | Only with `lockToAccount`: the key that only your Windows account can read. |

**`games.json`** contains:

- `generatedAt`, `scanSeconds`, `newDays` and `excludedDrives`;
- `drives[]`: `letter`, `label`, `totalBytes`, `freeBytes`, and `games`/`gameBytes` (duplicates not counted);
- `games[]`, sorted by name;
- `cleanup[]`: your cleanup entries, with `sizeBytes`;
- `skipped[]`: folders that looked like games but had no usable executable, with a `reason`. Useful when a game is missing.

Each entry in `games[]` has these fields:

| Field | Meaning |
|---|---|
| `id`, `name`, `source` | See above. `source` is one of `steam`, `epic`, `ea`, `ubisoft`, `gog`, `battlenet`, `riot`, `amazon`, `rockstar`, `xbox`, `other`. |
| `drive`, `installDir` | Where it lives. |
| `exe` | Detected (or overridden) executable. Empty if the game starts only through a launcher link. |
| `launch` | `{ type: "uri", target }` or `{ type: "exe", target, args }`. This is exactly what the server runs. |
| `sizeBytes` | Size on disk. Steam's own figure for Steam games; otherwise measured, without following links. |
| `installedAt` | Uninstall-registry install date, otherwise the folder's creation time. |
| `lastPlayed` | Steam's last-played time (Steam games only). Launches from the hub are stored in `state.json`, play sessions in `sessions.jsonl`. |
| `steamMinutes` | Steam's own play time for the game, in minutes (Steam games only). |
| `storeId` | Microsoft Store product id (Xbox app games), used to find their artwork. |
| `icon`, `header`, `cover`, `hero`, `logo` | File names in `data\art\`. Downloaded art in `data\covers\` takes priority; see [Artwork](artwork.md). |
| `defaultUri` | The launcher link the game would use without an `exe` override. |
| `customExe`, `manual` | `true` when the executable was overridden, or when the game was added by hand. |
| `warning`, `note`, `duplicateOf` | From the scanner or `overrides.json`. |

## Logs

In the logs folder of your data folder:

| File | Content |
|---|---|
| `logs\server.log` | Server start, launches, edits, background jobs and errors. Rotated to `server.log.1` at 1 MB. |
| `logs\scan.log` | Full transcript of the last scan and cover fetch. Overwritten on every scan. **Check my games** adds lines starting with `controllers:`. |
| `logs\watch.log` | One line per step of every launch watch: game started, window found, Game Hub minimized, game closed (with the minutes played), Game Hub restored. Lines from the controller helper start with `controller:`, from the outside-launch tracker with `tracker:`. Rotated to `watch.log.1` at 512 KB. |
