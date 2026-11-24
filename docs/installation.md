# Installation

Game Hub is a folder of scripts. Installing it means putting that folder somewhere, then creating shortcuts. It changes nothing else on your system: no registry entries, no services and no installer.

- [Requirements](#requirements)
- [Install](#install)
- [Where your data lives](#where-your-data-lives)
- [First run](#first-run)
- [Running from the command line](#running-from-the-command-line)
- [Changing the port](#changing-the-port)
- [Updating](#updating)
- [Uninstalling](#uninstalling)

## Requirements

- **Windows 10 or 11.** On Windows 10 version 2004 (May 2020) or later and on Windows 11, Game Hub starts without any console window and without VBScript. Older Windows 10 versions use the included VBScript helper instead.
- **Windows PowerShell 5.1.** It's preinstalled on both. The scripts start `powershell.exe` explicitly, so PowerShell 7 isn't used or needed.
- **A browser.** The hub opens as a standalone app window in Google Chrome (`chrome --app`), or in Microsoft Edge if Chrome isn't installed. Edge comes with Windows. Without either, it opens in your default browser. Minimizing while you play needs the app window.
- **A normal user account.** The server runs in your logged-in session and needs no administrator rights. Games need your desktop session to start, which is why Game Hub is not a Windows service.

## Install

1. **Choose where the program goes.** Game Hub keeps your settings and data apart from the program, in `%LOCALAPPDATA%\GameHub` (see [Where your data lives](#where-your-data-lives)), so any folder works. The usual place for an app that is just yours is `%LOCALAPPDATA%\Programs\GameHub`.

2. **Get the files.**

   ```powershell
   git clone https://github.com/izored/gamehub.git "$env:LOCALAPPDATA\Programs\GameHub"
   ```

   Alternatively, download `GameHub-<version>.zip` from the [latest release](https://github.com/izored/gamehub/releases/latest) and extract it there. It holds one `GameHub` folder. Each release lists the zip's SHA-256 checksum: `Get-FileHash .\GameHub-<version>.zip` shows yours.

3. **Unblock the scripts** if you downloaded a ZIP. Windows marks downloaded files, and PowerShell may refuse to run marked scripts. Run this from inside the folder:

   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```

4. **Create the shortcuts:**

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-shortcuts.ps1
   ```

   This creates three shortcuts with the Game Hub icon, `www\brand\icon.ico` (drawn first if it's missing). They start PowerShell through `conhost.exe --headless`, Windows' own way to run a console program with no window. On Windows 10 versions older than 2004 they use `wscript.exe gamehub.vbs` instead, since VBScript is being phased out of Windows.

   | Shortcut | Location | What it does |
   |---|---|---|
   | `Game Hub.lnk` | Desktop | Opens the hub, starting the server if needed |
   | `Game Hub.lnk` | Start menu › Programs | Same, and findable from Windows search |
   | `Game Hub Server.lnk` | Startup folder | Starts the server hidden at logon, so the hub opens instantly |

   Running `install-shortcuts.ps1` again is safe. It just refreshes the shortcuts, and moves shortcuts made by an older version off VBScript. You can turn the Startup entry off later in **Settings › Startup**.

> **About the execution policy.** The shortcuts and background jobs start PowerShell with `-ExecutionPolicy Bypass` for that one process. Your system-wide policy is not changed.

## Where your data lives

Everything that is yours is kept in one folder per Windows account, apart from the program:

| In `%LOCALAPPDATA%\GameHub` | What it is |
|---|---|
| `config.json` | Your settings ([Configuration](configuration.md)) |
| `overrides.json` | Your fixes: names, executables, hidden games, duplicates |
| `data\` | The game list, favorites, play time, artwork, custom covers, controller answers, and `data\backups` |
| `logs\` | What the server, the scanner and the helpers did ([Troubleshooting](troubleshooting.md)) |

**Settings › Backups** shows the folder. The program folder holds no personal data, so it can be replaced by an update, shared, or kept read-only.

- **A portable copy.** An empty file named `portable.txt` next to `server.ps1` keeps the data in the program folder instead, for a copy on a USB drive. Development copies use it too, so they don't share your everyday hub's data.
- **Somewhere else.** The `GAMEHUB_DATA` environment variable names another data folder.
- **Coming from an older version.** Versions before this one kept the data next to the scripts. The first start after updating copies `config.json`, `overrides.json`, `data\` and `logs\` to the data folder and checks every file arrived. The originals stay where they were, with a `DATA-MOVED.txt` note: once Game Hub works as before, you can delete them. While the note is there, they are never copied again.

## First run

Open **Game Hub** from the Desktop or Start menu. Then:

1. `open-hub.ps1` creates your [data folder](#where-your-data-lives) and copies `config.example.json` to `config.json` there, if you don't have one yet.
2. It starts `server.ps1` if nothing answers on the port, then opens the page in a Chrome or Edge app window.
3. With no game list yet, the page shows the [setup page](usage.md#the-setup-page): the drives to never read (USB drives are ticked for you), your game folders (suggested, added by hand, or found by an AI assistant), and a few options. **Nothing is scanned before you click *Scan my games*.**
4. The page fills in when the scan and the cover download finish, usually within a minute or two.

Afterwards:

- **Settings › Game folders** and **Settings › Drives** change what you chose on the setup page.
- **Fix the odd game** with the pen on its card: rename it, pick another executable, change the cover. See [Using Game Hub](usage.md#editing-a-game).

## Running from the command line

Every script takes an optional `-Root <folder>`, the program folder, which defaults to the script's own folder. The data folder follows the rules in [Where your data lives](#where-your-data-lives).

| Command | What it does |
|---|---|
| `conhost --headless powershell -NoProfile -ExecutionPolicy Bypass -File .\open-hub.ps1` | Open the hub without a console window. Starts the server if needed. This is what the Desktop and Start menu shortcuts run. |
| `conhost --headless powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1` | Start only the server, hidden. This is what the Startup shortcut runs. |
| `wscript gamehub.vbs` / `wscript gamehub.vbs server` | The same two, for Windows 10 versions older than 2004. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\open-hub.ps1` | Open the hub, with a console window. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1` | Run the server in the foreground. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scan-games.ps1` | Rescan now. Add `-NoCovers` to skip the artwork download. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\fetch-covers.ps1` | Fetch missing artwork only. Add `-Force` to retry earlier misses and re-download everyone's artwork. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\watch-game.ps1 -List` | Show whether the Game Hub app window is found, and which window is in front. The server runs this script by itself after every launch; see [While you play](usage.md#while-you-play). |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\controller-helper.ps1 -Test` | Bring Game Hub to the front once, as the View + Menu controller shortcut does. The server starts the helper itself when `controllerSummon` is on. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\check-controllers.ps1` | Look up which controllers each game understands by itself, as **Settings › Controllers › Check my games** does. Add `-Force` to look up every game again. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-translations.ps1` | Check the [translations](translating.md). |
| `node tools\test-pad-advice.js` | Check the DS4Windows suggestion rules (needs Node.js). |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-release.ps1` | Run every check, plus a privacy scan of what Git would publish. See [Contributing](../CONTRIBUTING.md#before-you-open-a-pull-request). |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\make-release.ps1 -Version 1.2.0` | Build a release zip from Git into `dist\`. Add `-Publish` to create the GitHub release too. |

The server also starts two small background helpers when their option is on: `controller-helper.ps1` (`controllerSummon`, on by default) and `track-games.ps1` (`trackOutsideLaunches`, off by default). Each allows a single copy of itself and stops on its own when its option is turned off.

The server is single-instance per port. Starting it twice is harmless: the second copy exits immediately.

Scans started from the command line don't notify an open page. The page reloads the catalog the next time its window gets focus.

## Changing the port

1. Change `port` in `config.json`, in your [data folder](#where-your-data-lives).
2. Run `install-shortcuts.ps1` again. The Startup shortcut's description mentions the port.
3. Restart the server (see [Uninstalling](#uninstalling) for how to stop it).

The web page always talks to the server it was loaded from, so nothing else needs changing.

## Updating

Your settings and data are in their own [data folder](#where-your-data-lives), so an update only replaces the program.

```powershell
git pull
```

If you installed from a zip, stop the server (step 1 of [Uninstalling](#uninstalling)), delete the program folder's contents and extract the new version in its place. Unblock the files again.

Then restart the server so it loads the new code. Static files (`www\`) are picked up on the next page load. Run `install-shortcuts.ps1` again when the changelog says the shortcuts changed.

New options in `config.example.json` are not copied into an existing `config.json`. Each one has a default that applies while it is missing, and most can be set in Settings. Check the [Changelog](../CHANGELOG.md).

Game Hub also backs up its own settings and library every day (Settings › Backups), so an update gone wrong can be undone from there.

## Uninstalling

1. **Stop the server and its helpers.** This command matches them by their path, so run it from the Game Hub folder:

   ```powershell
   $dir = (Get-Location).Path
   Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
     Where-Object { $_.CommandLine -like "*$dir\*.ps1*" } |
     ForEach-Object { Stop-Process -Id $_.ProcessId }
   ```

2. **Delete the shortcuts:**

   ```powershell
   Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Game Hub.lnk",
               "$([Environment]::GetFolderPath('Programs'))\Game Hub.lnk",
               "$([Environment]::GetFolderPath('Startup'))\Game Hub Server.lnk" -ErrorAction SilentlyContinue
   ```

3. **Delete the program folder.**

4. **Delete your data,** only if you don't want it any more: the `%LOCALAPPDATA%\GameHub` folder holds your settings, game list, play time and backups. Keep it, and a later install picks up where you left off.

Your games and launchers are untouched. Game Hub never moves, modifies or deletes game files.

If you used the DS4Windows rules, set every game back to *Keep DS4Windows on* and apply before uninstalling, or delete the Game Hub entries from DS4Windows' Auto Profiles yourself. A copy of the rules file from before Game Hub's first change is in `data\backups` in the data folder until you delete it.
