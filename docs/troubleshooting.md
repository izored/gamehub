# Troubleshooting

Start with the logs, in `%LOCALAPPDATA%\GameHub\logs` (**Settings › Backups** shows the data folder; a [portable copy](installation.md#where-your-data-lives) keeps them next to the scripts):

- `logs\server.log` records what the server did: launches, edits, errors.
- `logs\scan.log` is the full transcript of the last scan and cover fetch.
- `logs\watch.log` records what happened after each launch: game started, Game Hub minimized, game closed (with the minutes played), Game Hub restored. Lines starting with `controller:` come from the View + Menu helper, lines starting with `tracker:` from the outside-launch tracker.

## The hub doesn't open, or the page says it can't connect

- **Check the server.** Open `http://localhost:8790/api/status` in a browser. If nothing answers, start it by hand in the foreground so you can see errors:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
  ```

- **Port in use.** `server.log` then says *Cannot listen on port …*. Pick another `port` in `config.json` (see [Installation › Changing the port](installation.md#changing-the-port)).
- **Scripts blocked.** If you downloaded a ZIP, run `Get-ChildItem -Recurse | Unblock-File` in the folder.
- **Antivirus.** Some products block hidden PowerShell windows (`conhost --headless`, or `wscript.exe` on older Windows). Allow the Game Hub folder, or start it with `open-hub.ps1` directly.
- **The page says *Game Hub is locked*.** See [Game Hub says it is locked](#game-hub-says-it-is-locked).

## The setup page keeps coming back

The setup page appears whenever there is no game list (`data\games.json`) yet. If it comes back after *Scan my games*, the scan did not finish: a message says so, and `logs\scan.log` shows why. Fix the cause, then click *Scan my games* again.

## The setup page or the AI helper refuses a folder

Each folder gets a reason:

| Says | Meaning |
|---|---|
| *Folder not found* | It doesn't exist (check the spelling), or its drive isn't connected. |
| *On a drive Game Hub never reads* | Its drive is ticked *Never read*. Untick it first if that's a mistake. |
| *Already found through Steam* (or the Xbox app) | Every game there is already found through the launcher. |
| *Inside another folder in the list* | Its parent folder is already in the list, which covers it. |
| *Too broad* | A whole Windows drive, `Windows`, `Program Files`, `ProgramData`, `Users` or your user folder. Pick the folder that holds your games. |
| *Not a full folder path* | It must start with a drive letter, such as `D:\Games`. |
| *Already in your list* | Nothing to do. |

## A game is missing

1. **Did the scan look there?** Launcher games are found through their launcher. Anything else must be inside a **game folder** (Settings › Game folders), or be discoverable. See [Launchers](launchers.md).
2. **Is the drive excluded, or not a fixed disk?** The footer lists excluded drives. Removable, network and optical drives are never scanned.
3. **Was it skipped?** Look in `data\games.json` under `skipped`: those folders had no usable executable.
4. **Is it hidden?** Check **Settings › Hidden games**.
5. **Is it inside another game's folder?** The first source to claim a folder wins, and folders inside it are not scanned again.
6. If all else fails, use **Settings › Add a game**.

## Something that isn't a game shows up

- **For one entry:** pen › **Hide from hub**.
- **For a whole folder:** add its path to `ignore` in `config.json`, then restart the server and rescan.

If a common application keeps being discovered as a game, please open an issue so it can be added to the built-in exclusions.

## A game starts the wrong program, or doesn't start

- **Wrong executable.** Pen › **Executable** › **Browse…** and pick the right `.exe`. Add launch arguments if the game needs them.
- **"Executable not found".** The game moved or was uninstalled. Rescan.
- **The launcher opens but the game doesn't start.** For Steam, Epic and Ubisoft, the hub only hands the link to the launcher. Check that the launcher is signed in and the game shows as installed there.
- **Epic game with a ⚠ warning.** The Epic launcher has lost track of it, and the hub starts it from its executable. If the game insists on the launcher, re-link it in Epic: **Library › the game › Install**, with the folder *above* the game's folder as the install location. See [Launchers › Epic Games](launchers.md#epic-games).
- **EA game asks to sign in.** That's expected: the game opens the EA app itself.

## Game Hub doesn't minimize, or doesn't come back

Check `logs\watch.log` first. Each launch writes a few lines there.

- **Nothing logged for the launch.** Both options may be off: check **Settings › While you play**. If they're on, check `server.log` for *Could not start watch-game.ps1*. Some antivirus products block hidden PowerShell processes.
- ***did not start within 300 seconds*.** No program inside the game's install folder was running within 5 minutes. A launcher may be waiting for an update or a login, or the game may start a program installed somewhere else.
- ***Game Hub windows minimized: 0*.** The watcher didn't find a Game Hub app window. Run this in the Game Hub folder:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\watch-game.ps1 -List
  ```

  It must report *Game Hub window found*. Game Hub only minimizes its own app window, opened from the Desktop or Start menu shortcut. A Game Hub tab in a normal browser window is left alone.
- ***game in front: False*.** Game Hub minimized, but Windows kept another window in front. Click the game once.
- ***boot screen … waiting for the game window*.** Normal: the game showed a small splash or anti-cheat screen first, and Game Hub waited for the real window. *no game window after 90 seconds* means the game took longer than that. Game Hub then minimized anyway, and *opened late* shows when the game's window was brought to the front.
- **Game Hub comes back too late, or not at all.** It waits until every program inside the game's folder has closed. A game whose own launcher stays open in the background counts as running until that launcher closes too.

## The controller does nothing

- **Bring Game Hub to the front and press a button.** Browsers only report a controller to a page after a button has been pressed while that page is in front. The first press only shows the focus frame.
- **Make sure the browser sees it.** Game Hub works with every controller that Chrome or Edge reports with the standard layout. That covers DualSense and DualShock 4 over USB or Bluetooth, Xbox controllers, and DS4Windows' virtual Xbox controller. If a message says *the browser does not recognise its button layout*, connect the controller over USB, or run it through DS4Windows.
- **Each press counts twice, or the mouse pointer moves too.** Something else is turning the controller into a mouse or keyboard, usually Steam's *Desktop Layout* or a DS4Windows profile with mouse output. Turn that off outside games. In games, see [double input](controllers.md#every-button-pressed-twice-double-input).
- **It works in Game Hub but not in a game, or the other way round.** Game Hub doesn't change how games see your controller. Games read controllers in different ways, as explained under [Using a controller](usage.md#using-a-controller).

## A Steam game doesn't see my controller

Steam shows the controller as connected, but the game ignores it.

1. **Turn Steam Input on for that game.** This is the most common cause. Steam Input can be switched off for a single game, and then a PlayStation controller may not reach the game at all. In Steam, open **Library › right-click the game › Properties › Controller**, or the controller icon while the game runs. Turn on Steam Input: a switch such as *Use Steam Input compatibility layer*, or an override set to *Enable Steam Input*. Then restart the game.
2. **Using DS4Windows for that game?** Do the opposite: leave Steam Input off for that game, so it sees only DS4Windows' Xbox controller and not two controllers.
3. **Restart the game with the controller already connected,** and keep the game in front while it loads. Many games only look for controllers when they start. Steam only passes the controller to a game while that game's window is in front; otherwise it uses its desktop layout.
4. **Still nothing?** Steam's own log shows which layout it used and when: `Steam\logs\controller.txt`. *Queueing activation … app: <the game's app id>* means the game's layout; *app: 413080* is Steam's desktop layout.

## Play time is missing or looks wrong

- **The game was started outside Game Hub** (from Steam, a desktop shortcut, its own launcher). Turn on **Settings › While you play › Count games started outside Game Hub**. Steam games are covered anyway, through Steam's own play time.
- **Sessions shorter than a minute** are not recorded.
- **A Steam game shows more hours than you played through Game Hub.** That's Steam's own total, which includes every session: Game Hub shows the larger of the two.
- **A game whose program runs from outside its install folder** (some launchers start the real game elsewhere) can't be timed. `logs\watch.log` then says it *did not start within 300 seconds*.

## Wrong or missing cover

- **Wrong cover.** Pen › **Search Steam artwork** and pick the right entry, or upload your own image.
- **Missing cover.**
  - **Settings › Fetch missing covers** retries.
  - Games already recorded as misses are skipped. Run `fetch-covers.ps1 -Force`, or remove the game from `data\covers\_misses.json`.
  - For Microsoft Store games, set `msStoreId` in `overrides.json`.
  - Otherwise, upload an image.
- **Changed image not showing.** Reload the page with `Ctrl+F5`.

See [Artwork](artwork.md).

## A banner says a file was repaired

When Game Hub starts, it checks its main files: `config.json`, `overrides.json`, the game list and favorites (`data\games.json`, `data\state.json`). A crash or a power cut can leave one empty or half-written; Game Hub then puts back the newest good copy from its [backups](usage.md#backups) and shows which file it repaired. Anything changed since that backup is lost for that file. Close the banner with ×.

## Game Hub says it is locked

Game Hub is locked to one Windows account (Settings › Security, `lockToAccount`).

- **It's your account:** open Game Hub from its Desktop or Start menu shortcut. Opening `http://localhost:8790` from a bookmark or another browser doesn't carry the key; the shortcut does.
- **To turn the lock off:** Settings › Security, or set `lockToAccount` to `false` in `config.json` and restart the server.

## A DS4Windows suggestion is wrong

PCGamingWiki and Steam's labels can be wrong or out of date, and many games behave differently over USB and Bluetooth. In **Settings › Controllers**, click **Tell Game Hub** next to the game and say what happens: your answer replaces the suggestion, and **Forget my answer** undoes it. Also check that the controllers at the top are connected the way you play. More in [Controllers › Which games need DS4Windows?](controllers.md#which-games-need-ds4windows)

## The controller shortcut or a DS4Windows rule does nothing

See [Controllers › Troubleshooting](controllers.md#troubleshooting).

## The page is in the wrong language, or a translation is wrong

Pick the language in **Settings › Language**. *Automatic* follows your browser's language list. Wrong or odd text in a translated language can be reported from the link under the language setting; see [Translating](translating.md).

## Settings won't save a folder

- *"Folder not found"*: the new folder doesn't exist, or its drive isn't connected.
- *"… is a drive Game Hub never reads"*: it's on a drive marked *Never read* (`excludeDriveLetters` or `excludeVolumeLabels`).

## My manual edits to config.json disappeared

The server keeps `config.json` in memory and rewrites it when you change anything in Settings. Stop the server, or restart it, after editing the file by hand. See [Configuration](configuration.md).

## The file picker doesn't appear

The Windows file dialog opens on the desktop of the user running the server. If the server was started from another account or an elevated console, the dialog opens there. Start the server normally, from the shortcut or at logon.

## "A scan is already running"

Only one background job runs at a time. Wait for it to finish. Large libraries spend most of their scan time measuring folder sizes. If a scan seems stuck, check `logs\scan.log`.

## Reset everything

1. Stop the server.
2. Delete `data\` to reset the library, favorites, play time, backups and artwork. (Keep a copy of `data\backups` if you may want something back.)
3. Optionally delete `config.json` and `overrides.json` as well.
4. Start the hub again. The setup page appears.
