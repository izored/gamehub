# Instructions for AI assistants

This folder is **Game Hub**, a local launcher for every game on a Windows PC (see [README.md](README.md)). You are an AI assistant working with a user here. Work out which job they want:

- **A. Set up or tidy their game library.** Install Game Hub, scan their drives, and get every game linked: the right name, executable, launcher link and cover, with no duplicates. Follow the **[Setup playbook](#a-setup-playbook)** below.
- **B. Change Game Hub's code.** Follow **[Changing the code](#b-changing-the-code)** and [CONTRIBUTING.md](CONTRIBUTING.md).

If it's unclear, ask.

---

## A. Setup playbook

### Goal

Every game the user has installed:

- appears **once** in Game Hub;
- has the **right name** and a **cover**;
- **launches** correctly, through its launcher where it has one.

Junk is hidden. Duplicate installs are identified, and the user knows which copy to keep.

The user stays in control. You explain, propose and ask; they decide.

### Ground rules (always apply)

1. **Excluded drives come first.** Before any scan or file search, ask which drives must never be read: removable drives, backup disks, anything private. Record them in `config.json`. From then on, never read, list or search those drives, including with your own commands. Listing drive letters, labels and sizes with `Get-CimInstance Win32_LogicalDisk` is fine: it reads no files.
2. **Never delete, move or rename game files**, and never modify launcher files, manifests or databases (Steam, Epic, EA, Ubisoft, GOG, Battle.net, Riot, Amazon, Rockstar, the Xbox app). DS4Windows rules are set by the user in Game Hub's **Settings › Controllers**, never by editing DS4Windows' files yourself. Duplicates and leftovers are *reported*, through `duplicateOf` and `cleanup` in `overrides.json`. If the user wants space back, give them the exact path and size, and recommend uninstalling through the launcher. They do the deleting.
3. **Only write Game Hub's own files:**
   - `config.json`;
   - `overrides.json`;
   - Game Hub's generated cache under `data\covers` (only when replacing artwork).

   They all live in Game Hub's **data folder**, `%LOCALAPPDATA%\GameHub`, not next to the scripts (see [Where your data lives](docs/installation.md#where-your-data-lives)). The commands below call it `$d`. Back up a file before you change it, and check it is valid JSON afterwards.
4. **Ask before launching any game.** Launching starts programs and may trigger updates, anti-cheat or online sign-in. Test one game at a time, and only with a yes.
5. **Install nothing, change no system settings.** That means:
   - no winget, Chocolatey, npm or PowerShell modules;
   - no execution-policy, Defender, firewall or registry changes.

   Game Hub needs none of this. Run its scripts with `powershell -NoProfile -ExecutionPolicy Bypass -File …`, which affects only that one process.
6. **Never handle accounts or passwords.** Re-linking a game inside a launcher is done by the user, in that launcher's window. You tell them exactly what to click.
7. **Keep it private.** Paths and game names are personal. Don't put them into web searches, URLs or anything outside this conversation. Game Hub's own artwork lookups are the only network traffic the setup needs.
8. **Evidence over guesses.** When you claim something ("this copy is the one you play", "this is the right executable"), say what you based it on, and say so when the evidence is weak.
9. **If antivirus blocks a command** (for example *ScriptContainedMaliciousContent*), stop. Tell the user what was blocked, and continue with another approach, such as the Game Hub UI. Never try to get around security software.
10. **Talk like a helpful person.** Use the user's language and plain words. Before each phase, say what you are about to do. After it, say what you found or changed.

### How to work

- **If you can run commands** (an agent with a terminal): run the PowerShell commands below yourself, from the Game Hub folder. Read their output before moving on.
- **If you're a chat assistant without a terminal:** give the user **one command at a time** in a code block. Ask them to run it in PowerShell from the Game Hub folder and paste the output, and keep requested outputs short. For file edits, give them the complete snippet to run.
- **Work through the phases in order.** Don't start the scan (Phase 5) before the exclusions (Phase 2) are saved. Opening the hub early is harmless: with no game list it shows its setup page, which scans nothing until the user clicks *Scan my games*.
- **The setup page is an alternative to Phases 2 to 5.** It asks for the never-read drives (USB drives pre-ticked), suggests game folders, can write a prompt for an AI to find more, and runs the first scan. If the user prefers it, let them use it, then continue from Phase 6. Settings in the page (Drives, Game folders) write the same `config.json` keys you would.
- **Keep a running list** of what you changed and what the user still has to do. You'll need it for the final report.

### Prelude

From Phase 4 on, the commands use the variables below.

- **Agents:** most run each command in a fresh shell, so start each command with this block.
- **Chat mode:** the user's PowerShell window keeps variables, so they run it once, and again after `config.json` changes.

```powershell
$d    = if ($env:GAMEHUB_DATA) { $env:GAMEHUB_DATA } elseif (Test-Path .\portable.txt) { (Get-Location).Path } else { "$env:LOCALAPPDATA\GameHub" }   # Game Hub's data folder
$c    = Get-Content "$d\config.json" -Raw | ConvertFrom-Json
$port = $c.port
$ex   = @(@($c.excludeDriveLetters) + @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.VolumeName -and @($c.excludeVolumeLabels) -contains $_.VolumeName } | ForEach-Object DeviceID) | Select-Object -Unique)   # never read these
$cat  = if (Test-Path "$d\data\games.json") { Get-Content "$d\data\games.json" -Raw | ConvertFrom-Json }
$h    = @{ 'X-GameHub' = '1' }   # header required by every POST to the hub
"Never read: $($ex -join ', ')"
```

### Phase 1: Check the folder and the PC

Ask where Game Hub is, or find the folder that contains `server.ps1`, `scan-games.ps1` and `config.example.json`. All commands below run from that folder.

```powershell
[Environment]::OSVersion.Version.ToString()     # 10.0.x = Windows 10/11
(Get-Command powershell.exe).Source             # Windows PowerShell 5.1 must exist
$d    = if ($env:GAMEHUB_DATA) { $env:GAMEHUB_DATA } elseif (Test-Path .\portable.txt) { (Get-Location).Path } else { "$env:LOCALAPPDATA\GameHub" }   # Game Hub's data folder
Test-Path "$d\config.json", "$d\data\games.json"   # False, False = fresh install
Test-Path .\config.json                          # True = an older version's data, still next to the scripts: the first start copies it to $d
$port = if (Test-Path "$d\config.json") { (Get-Content "$d\config.json" -Raw | ConvertFrom-Json).port } else { 8790 }
try { Invoke-RestMethod "http://localhost:$port/api/status" -TimeoutSec 3 } catch { 'server not running' }
```

Notes:

- **Where the program is.** Any folder works, even `Program Files`: Game Hub keeps the user's data apart, in `$d`. The usual place for the program is `%LOCALAPPDATA%\Programs\GameHub`. An empty `portable.txt` next to `server.ps1` keeps the data in the program folder instead (a copy on a USB drive).
- **Downloaded ZIP:** if the files came from a ZIP, unblock them with `Get-ChildItem -Recurse | Unblock-File`.

### Phase 2: Decide what must never be read

List the drives. This reads only metadata:

```powershell
Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, VolumeName,
  @{n='Type';e={@{2='Removable';3='Fixed';4='Network';5='CD/DVD'}[[int]$_.DriveType]}},
  @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB)}} | Format-Table -AutoSize
# how each drive is connected: a USB SSD shows BusType USB even when its Type above says Fixed
Get-Partition | Where-Object DriveLetter | ForEach-Object { [pscustomobject]@{ Drive = "$($_.DriveLetter):"; BusType = (Get-Disk -Number $_.DiskNumber).BusType } } | Format-Table -AutoSize
```

Explain the rules to the user, then **ask which drives Game Hub must never read**:

- Game Hub only scans **Fixed** drives.
- Many USB SSDs report themselves as Fixed, so they *will* be scanned unless excluded. The `BusType` column shows them as `USB`: suggest excluding every USB drive unless the user keeps games on it on purpose.
- A volume label is the safer way to exclude a removable drive, because its letter can change.

If the **server is running**, stop it before editing `config.json`. It keeps the file in memory and would overwrite your edit later:

```powershell
$dir = (Get-Location).Path
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$dir\server.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId }
```

Then create `config.json` if needed, and save the exclusions. Replace the example values with the user's answer, or use empty lists:

```powershell
$d    = if ($env:GAMEHUB_DATA) { $env:GAMEHUB_DATA } elseif (Test-Path .\portable.txt) { (Get-Location).Path } else { "$env:LOCALAPPDATA\GameHub" }   # Game Hub's data folder
if (-not (Test-Path "$d\config.json")) { New-Item -ItemType Directory -Force $d | Out-Null; Copy-Item .\config.example.json "$d\config.json" }
Copy-Item "$d\config.json" "$d\config.json.$(Get-Date -Format yyyyMMdd-HHmmss).bak"
$c = Get-Content "$d\config.json" -Raw | ConvertFrom-Json
$c.excludeDriveLetters = @('X:')          # the user's answer: letters with a colon, or @()
$c.excludeVolumeLabels = @('MY-USB')      # the user's answer: volume labels, or @()
$c | ConvertTo-Json -Depth 5 | Set-Content "$d\config.json" -Encoding UTF8
Get-Content "$d\config.json" -Raw | ConvertFrom-Json | Select-Object excludeDriveLetters, excludeVolumeLabels
```

From now on, use the [prelude](#prelude) before any command that touches files. It computes `$ex`, the drives you must skip.

### Phase 3: Install

Ask whether the user wants Game Hub to **start with Windows**. It runs a small hidden server at logon, which makes the hub open instantly. Then create the shortcuts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-shortcuts.ps1
```

This creates:

- `Game Hub.lnk` on the Desktop and in the Start menu;
- `Game Hub Server.lnk` in the Startup folder.

They start PowerShell hidden through `conhost.exe --headless` (or `gamehub.vbs` on Windows 10 versions older than 2004).

If the user said **no** to starting with Windows, remove the Startup shortcut:

```powershell
Remove-Item "$([Environment]::GetFolderPath('Startup'))\Game Hub Server.lnk"
```

They can turn it back on later in **Settings › Startup**.

### Phase 4: Tell the hub where games are

Steam, Epic, Ubisoft, GOG, Battle.net, Riot, Amazon, Rockstar and Xbox app games are found through their launchers, wherever they are installed. Everything else needs a **game folder**: a folder whose every sub-folder is one game (`gameRoots` in `config.json`). The launchers' own install folders (Epic, EA, Ubisoft, GOG, Battle.net) are worth adding too: scanning them also finds games the launcher forgot after a reinstall. Steam libraries and the Xbox app's `XboxGames` folders never need adding.

1. **Ask the user** where their games live: drives, folders, and any launcher that forgot its games after a reinstall.
2. **With their permission, look for likely folders.** Check only the top level of allowed fixed drives, never deeper and never excluded drives:

   ```powershell
   Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $ex -notcontains $_.DeviceID } | ForEach-Object {
     Get-ChildItem "$($_.DeviceID)\" -Directory -ErrorAction SilentlyContinue | Where-Object Name -match 'game|steam|epic|origin|gog|ubisoft|uplay|xbox|^ea' | Select-Object -ExpandProperty FullName }
   ```

3. **Propose the list and agree it with the user.** Rules for picking folders:
   - A good game folder contains **only** games: `D:\Games`, `C:\Program Files\EA Games`, `C:\Program Files\Epic Games`, `C:\Program Files (x86)\GOG Galaxy\Games`.
   - A Steam library (`…\SteamLibrary`) doesn't need to be listed. Steam reports it.
   - A whole drive root (`E:\`) is allowed, but every top-level folder then counts as a game. List the non-game folders under `ignore`.
4. **Save `gameRoots` and `ignore`.** Stop the server first if it's running (see Phase 2), and back up the file:

   ```powershell
   $c = Get-Content "$d\config.json" -Raw | ConvertFrom-Json
   $c.gameRoots = @('C:\Games', 'D:\Games')
   $c.ignore    = @('C:\Program Files\Epic Games\Launcher')
   $c | ConvertTo-Json -Depth 5 | Set-Content "$d\config.json" -Encoding UTF8
   ```

### Phase 5: First scan

Tell the user the scan reads the allowed drives. After it, Game Hub downloads **official artwork** from Steam, Epic and the Microsoft Store, sending only game titles or store ids. Then run it.

- **Server not running:**

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan-games.ps1
  ```

  Add `-NoCovers` to skip artwork for now. Note that the hub's **Rescan** button always fetches artwork.
- **Server running:** use its background job, so two scans never run at once:

  ```powershell
  $h = @{ 'X-GameHub' = '1' }
  Invoke-RestMethod -Method Post "http://localhost:$port/api/rescan" -Headers $h -ContentType 'application/json' -Body '{}'
  do { Start-Sleep -Seconds 3; $s = Invoke-RestMethod "http://localhost:$port/api/status" } while ($s.scanning)
  ```

Then summarize the result for the user:

```powershell
$cat = Get-Content "$d\data\games.json" -Raw | ConvertFrom-Json
$cat.games | Group-Object source | Select-Object Name, Count
$cat.games | Sort-Object source, name | Format-Table id, name, source, drive, @{n='launch';e={$_.launch.type}}, @{n='target';e={$_.launch.target}}, warning -AutoSize -Wrap
$cat.skipped | Format-Table reason, path -AutoSize -Wrap
```

`source` is one of `steam`, `epic`, `ea`, `ubisoft`, `gog`, `battlenet`, `riot`, `amazon`, `rockstar`, `xbox` or `other` (shown as *Standalone*). The `id` is how you refer to a game in `overrides.json`.

### Phase 6: Review and link, game by game

Go through these checks with the user. Batch similar fixes together, and confirm the batch before applying it in Phase 7.

#### 6.1 Missing games

Ask the user which games they expect to see, or show the list and ask what's missing. For each missing game, check these causes in order:

1. **Its folder isn't under a game folder.** Add the parent folder to `gameRoots`, or add just this game: **Settings › Add a game**, `POST /api/game/add`, or an `add` entry in `overrides.json`.
2. **It's in `skipped`.** No usable executable was found. Inspect the folder (see 6.4), then add it by hand with the right executable.
3. **It's hidden** (`hidden: true` in `overrides.json`).
4. **It's inside another game's folder.** The first source to claim a folder wins.
5. **It's on an excluded drive.** Tell the user, and don't touch it.

#### 6.2 Things that aren't games

Tools, launchers, benchmarks and so on. Either hide them (`hidden: true`, or the pen › **Hide from hub**), or add their folder to `ignore` in `config.json`.

#### 6.3 Names

Fix wrong or ugly names with a `name` override. Keep official titles, for example *Marvel's Guardians of the Galaxy*.

#### 6.4 Executables

Check `launch.target` for `exe` launches. To see the candidates in a game's folder:

```powershell
$dir = 'D:\Games\Some Game'
Get-ChildItem -LiteralPath $dir -Recurse -Depth 4 -Filter *.exe -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending |
  Select-Object -First 15 @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, @{n='Product';e={$_.VersionInfo.ProductName}}, FullName | Format-Table -AutoSize -Wrap
```

What to choose:

- **Prefer** the game's own executable, usually the largest one named after the game, with a matching *Product* name.
- **Avoid** redistributables, crash reporters, anti-cheat installers and `*Setup*`.
- **Some games are meant to start through a wrapper.** Examples are an `…AntiCheat…Launcher.exe` named by the EA installer data, or a small root `.exe` that starts the real one. If the current target is such a wrapper, leave it.
- **Bypassing a launcher is a trade-off.** For Steam, Epic, Ubisoft, Battle.net, Riot and Amazon games, an `exe` override skips the launcher, and with it cloud saves, updates and the overlay. Suggest it only when the launcher link doesn't work.

#### 6.5 Launcher links

| Launcher | What Game Hub does | What the user may need to do |
|---|---|---|
| Steam | `steam://rungameid/<appid>` | Nothing. If a game folder exists under `steamapps\common` but Steam shows the game as not installed, click **Install** in Steam and pick that library. Steam finds the files and verifies them instead of downloading. Libraries on another drive: **Steam › Settings › Storage › Add drive**. |
| Epic (registered) | Epic launcher link | Nothing. |
| Epic (⚠ *Not registered in the Epic launcher*) | Starts the game's `.exe` directly | Usually nothing. If the game demands the Epic launcher, re-link it: **Epic › Library › the game › Install**, and set the install location to the folder *above* the game's folder. For `F:\Games\HogwartsLegacy`, choose `F:\Games`. Epic adds its own folder name; when that matches, it verifies the files instead of downloading. If it starts downloading the whole game, cancel it: the folder name doesn't match Epic's. |
| EA app | Starts the `.exe` named by the EA installer data | Nothing for launching. The game brings up the EA app itself. If the EA app lists the game as not installed and offers to locate an existing installation, the user can point it to the folder. |
| Ubisoft Connect | `uplay://launch/<id>/0` | Nothing. If Ubisoft Connect shows the game as not installed, its game page offers **Locate installed game**. |
| GOG Galaxy | Starts the `.exe` from GOG's registry entry, with its launch parameters | Nothing. GOG games have no DRM. |
| Battle.net | `battlenet://<code>` for known games, otherwise the `.exe` | Nothing, as long as the Battle.net app is installed and signed in. |
| Riot Client | `RiotClientServices.exe --launch-product=<product>` | Nothing, as long as the Riot Client is signed in. |
| Amazon Games | `amazon-games://play/<id>` | Nothing, as long as Amazon Games is installed and signed in. |
| Rockstar | Starts the `.exe`, which opens the Rockstar Games Launcher | Nothing. |
| Xbox app (Store, Game Pass) | `shell:AppsFolder\<package>!<app>`, like the Start menu | Nothing. Don't set an `exe` override: most of these games only run through Windows' own entry. |
| Standalone (DRM-free, emulators…) | Starts the `.exe` | Nothing. |

Launcher re-linking is the user's action. Give the exact folder path, and wait for them to confirm before rescanning.

#### 6.6 Duplicates

The same game can be installed twice, for example after a launcher reinstall or bought on two stores. Find candidates:

```powershell
$n = { param($s) ($s -replace '[^A-Za-z0-9]', '').ToLower() }
$cat.games | Group-Object { & $n $_.name } | Where-Object Count -gt 1 | ForEach-Object { $_.Group |
  Select-Object id, source, installDir, @{n='GB';e={[math]::Round($_.sizeBytes/1GB,1)}}, lastPlayed, duplicateOf } | Format-Table -AutoSize
```

Also look over the full list yourself for near-duplicates the command misses, such as a demo or prologue next to the full game, or "Edition" suffixes. Also look at `skipped`: a partial re-download often lands there.

Decide which copy is in use, strongest evidence first. Use read-only commands only, and only on allowed drives:

1. **Ask the user.** They often know.
2. **Game Hub's launch and play history:**

   ```powershell
   (Get-Content "$d\data\state.json" -Raw | ConvertFrom-Json).launches
   if (Test-Path "$d\data\sessions.jsonl") { Get-Content "$d\data\sessions.jsonl" | ConvertFrom-Json | Group-Object id | Select-Object Name, Count, @{n='Minutes';e={($_.Group | Measure-Object minutes -Sum).Sum}} }
   ```

   Steam's last-played time is in `lastPlayed`, its play time in `steamMinutes`.
3. **Launcher logs:**
   - EA app logs (`%LOCALAPPDATA%\Electronic Arts\EA Desktop\Logs`) record launches with the executable path.
   - Unreal Engine games write logs and crash reports under `%LOCALAPPDATA%\<ProjectName>\Saved\`, which often contain the path of the copy that ran.
4. **Recently changed files inside each copy.** Settings, saves, logs:

   ```powershell
   Get-ChildItem -LiteralPath 'D:\Games\Some Game' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 LastWriteTime, FullName
   ```

   This is weak evidence: updates and file verification also write files.

When unsure, say so and let the user decide. Then, on the copy **not** in use, set `duplicateOf` to the id of the copy to keep, plus a `note` with your evidence. Game Hub then hides it from the library and lists it in **Cleanup** with its size. Leftover folders that aren't games, such as an abandoned download or an installer archive, go into `cleanup`, with `path`, `title`, `keep` and `note`. Never delete.

#### 6.7 Covers

Games still without artwork after the scan:

```powershell
(Invoke-RestMethod "http://localhost:$port/api/settings").coverMisses
```

The server must be running for this. Fixes:

| Situation | Fix |
|---|---|
| Sold on Steam under another title | Set `steamAppId`, or use the pen › **Search Steam artwork**. |
| Microsoft Store game | Xbox app games use their own Store id automatically. For others, set `msStoreId`, the 12-character id from the Store URL. |
| Neither | The user uploads an image with the pen › **Upload cover…**. |

**Replace a wrong cover immediately** with Steam artwork:

```powershell
$h = @{ 'X-GameHub' = '1' }
Invoke-RestMethod -Method Post "http://localhost:$port/api/cover/steam" -Headers $h -ContentType 'application/json' -Body '{"id":"<game id>","appid":<steam app id>}'
```

`fetch-covers.ps1` only fills games that have **no** cover. Before using `msStoreId` to replace an existing wrong cover, delete that game's downloaded `$d\data\covers\<id>-cover.*` and `<id>-hero.*`, but never `*.custom.*`, then remove the game from `data\covers\_misses.json` and run **Fetch missing covers**.

### Phase 7: Apply changes safely

**Option 1: the hub UI or API.** Use these for name, executable, arguments, hide and add. They're validated by the server, applied at once, and stored in `overrides.json` for you.

| Change | Endpoint and body |
|---|---|
| Rename, change executable or arguments, hide | `POST /api/game/save` `{ "id", "name"?, "exe"?, "args"?, "hidden"? }` |
| Add a game | `POST /api/game/add` `{ "name", "exe", "args"? }` |

Every POST needs the header `X-GameHub: 1`. The full API is in [docs/api.md](docs/api.md).

Game Hub also backs up `config.json`, `overrides.json` and its data every day (**Settings › Backups**). Your own `.bak` copies are still required before you edit a file.

**Option 2: `overrides.json`.** Needed for `duplicateOf`, `note`, `warning`, `uri`, `steamAppId`, `msStoreId`, `noArt`, `add` and `cleanup`. Field reference: [docs/configuration.md](docs/configuration.md#overridesjson). This file is safe to edit while the server runs.

```powershell
$path = "$d\overrides.json"
if (Test-Path $path) { Copy-Item $path "$path.$(Get-Date -Format yyyyMMdd-HHmmss).bak" }
$o = if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $o.PSObject.Properties['games'])   { $o | Add-Member -NotePropertyName games -NotePropertyValue ([pscustomobject]@{}) }
if (-not $o.PSObject.Properties['add'])     { $o | Add-Member -NotePropertyName add -NotePropertyValue @() }
if (-not $o.PSObject.Properties['cleanup']) { $o | Add-Member -NotePropertyName cleanup -NotePropertyValue @() }
function Set-Override([string]$id, [string]$field, $value) {
  if (-not $o.games.PSObject.Properties[$id]) { $o.games | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{}) }
  $o.games.$id | Add-Member -NotePropertyName $field -NotePropertyValue $value -Force
}
# --- one line per change, for example:
Set-Override 'steam-1234560' 'duplicateOf' 'other-mygame'
Set-Override 'steam-1234560' 'note' 'Steam copy never launched; the D: copy is the one in use.'
Set-Override 'other-somegame' 'name' 'Some Game: Definitive Edition'
# ---
$o | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding UTF8
Get-Content $path -Raw | ConvertFrom-Json | Out-Null; 'overrides.json is valid'
```

If you have a file-editing tool, you may edit the JSON directly instead. Keep it valid, and check it with the last line above.

**Then rescan** (Phase 5) and compare with the user. Overrides are applied during the scan. Confirm that:

- every change shows up;
- nothing else changed unexpectedly: the game count, and no names that changed by themselves.

### Phase 8: Test launches (with permission)

Ask which games to test. One game per launch type the user has (Steam, Epic, EA, Ubisoft, GOG, Battle.net, Riot, Amazon, Rockstar, Xbox app, standalone) is enough. Do them one at a time:

```powershell
$h = @{ 'X-GameHub' = '1' }
Invoke-RestMethod -Method Post "http://localhost:$port/api/launch" -Headers $h -ContentType 'application/json' -Body '{"id":"<game id>"}'
```

Alternatively, ask the user to click the card in the hub. After each launch, ask the user whether the game (or its launcher) opened correctly, and fix anything that didn't (6.4, 6.5).

Also ask whether Game Hub got out of the way and came back after they quit. That's on by default (**Settings › While you play**). If it didn't, read `logs\watch.log` in the data folder and follow [Troubleshooting](docs/troubleshooting.md#game-hub-doesnt-minimize-or-doesnt-come-back). Mention that the hub can be driven with a controller ([Using a controller](docs/usage.md#using-a-controller)).

If the user plays Steam games with a PlayStation controller, remind them to check that **Steam Input** is on for each of those games: Steam › Library › right-click the game › Properties › Controller. When it's off, Steam shows the controller as connected but the game ignores it. If they use DS4Windows for a game, Steam Input should stay off for that game instead. See [Troubleshooting](docs/troubleshooting.md#a-steam-game-doesnt-see-my-controller). Never change Steam settings yourself.

If they use **DS4Windows** and have to quit it for some games, point them to **Settings › Controllers › DS4Windows: per-game rules** (see [Controllers](docs/controllers.md#ds4windows-rules-per-game)). They choose and apply the rules there; don't edit DS4Windows' files. **Check my games** there suggests a rule for each game, and **Tell Game Hub** lets them correct a suggestion from what they saw in the game.

If the server isn't running yet, start it, or open the hub, with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\open-hub.ps1
```

### Phase 9: Wrap up

Open the hub for the user (`powershell -NoProfile -ExecutionPolicy Bypass -File .\open-hub.ps1`), then give a short report:

```
Game Hub is set up.
- Library: <N> games (Steam <n>, Epic <n>, EA <n>, Ubisoft <n>, ... Standalone <n>), all with covers / <k> without.
- Never read: <drives>.
- Game folders: <list>.
- Changes made: <renames, executables, hidden, duplicates marked, games added>
  (backups: config.json.<stamp>.bak, overrides.json.<stamp>.bak).
- Tested launches: <games and result>.
- Your to-do list:
  - <re-link X in Epic: Install > choose F:\Games>
  - <decide whether to remove the duplicate of Y (path, size) via the launcher>
- Starts with Windows: <yes/no>.
```

Mention that the `.bak` files can be deleted once the user is happy, and point out what they may not know about: **Settings › Backups** (daily backups and a CSV of their games), play time and the *Most played* row, **Settings › Language**, and, on a PC with other Windows accounts, **Settings › Security**. For general safety advice, link [Staying safe](docs/staying-safe.md).

---

## B. Changing the code

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. In short:

- **No dependencies and no build step.**
  - The PowerShell scripts must run under **Windows PowerShell 5.1**: no `??`, `?.`, ternary or `-Parallel`.
  - `.ps1` and `.vbs` files must be **ASCII only**. Build other characters with `[char]0x…`.
  - Every text the page shows goes through `t()` / `data-i18n` with its English text in `www/lang/en.json`; run `tools\check-translations.ps1`.
  - The web app is vanilla JavaScript. Never put game data into `innerHTML`.
- **Preserve the safety properties:**
  - launch by catalog id only, with the URI-scheme allowlist;
  - Host, Origin and `X-GameHub` checks;
  - never read excluded drives;
  - never delete user files;
  - the launch watcher, the tracker and the controller helper only read window titles, executable paths and controller state, and only move the Game Hub window;
  - the setup page and folder checks never read never-read drives; restores only write Game Hub's own files; DS4Windows changes stay limited to the rules Game Hub wrote;
  - with `lockToAccount` on, every data and action request needs the lock cookie, and a missing key means everything is refused;
  - controller input is ignored while the hub isn't the window in front.
- **Keep the monochrome UI.** Colour comes from game art only.
- **Before finishing:**
  - parse all scripts with PowerShell 5.1;
  - run the ASCII check;
  - run `node --check www/app.js` and `node --check www/gamepad.js`;
  - run `tools\check-translations.ps1`;
  - run `tools\check-release.ps1`: it does all of the checks above in one go, plus the privacy scan that keeps the user's paths and drive names out of the repository;
  - test the affected flows by hand;
  - update the docs;
  - add a line under **[Unreleased]** in [CHANGELOG.md](CHANGELOG.md).
- **Never commit** `config.json`, `overrides.json`, `data/`, `logs/`, `dist/`, `DATA-MOVED.txt`, `portable.txt` or `*.bak`. They normally live in the data folder anyway; the pre-commit hook (`git config core.hooksPath .githooks`) refuses them.
