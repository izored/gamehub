# Using Game Hub

- [The setup page](#the-setup-page)
- [The home page](#the-home-page)
- [Game cards](#game-cards)
- [While you play](#while-you-play)
- [Play time](#play-time)
- [Using a controller](#using-a-controller)
- [Browsing and search](#browsing-and-search)
- [Editing a game](#editing-a-game)
- [Adding a game](#adding-a-game)
- [Settings](#settings)
- [Backups](#backups)
- [Storage and Cleanup](#storage-and-cleanup)
- [Keyboard shortcuts](#keyboard-shortcuts)

## The setup page

The first time you open Game Hub (when it has no game list yet), a setup page appears instead of the library. Nothing is scanned until you finish it.

1. **Drives.** Tick the drives Game Hub must never read: a USB SSD, a backup disk, a drive you share. USB and removable drives are ticked for you, even the ones Windows calls fixed. The Windows drive is always read. Here Game Hub only looks at each drive's name, size and type.
2. **Game folders.**
   - *Found automatically through their launchers* lists the folders Steam and the Xbox app manage. Their games are found wherever they are, so there is nothing to add.
   - Below are the suggested game folders, ticked: your current ones, the folders of the other launchers (Epic, EA, Ubisoft, GOG, Battle.net: scanning them also finds games the launcher has forgotten), and top-level folders named like a game folder (`Games`, `Jeux`, `SteamLibrary`...). Untick anything that isn't a game folder. Every sub-folder of a ticked folder counts as one game.
   - **Add folder...** opens the Windows folder picker.
   - **Find my game folders with an AI** opens the [AI helper](#find-your-game-folders-with-an-ai).
3. **Options.** Start with Windows, minimize Game Hub while you play and bring it back afterwards, the language, and (only on a PC with other Windows accounts) the [lock](../SECURITY.md#optional-lock-to-your-windows-account).

Click **Scan my games**. The scan takes a minute or two, then covers download, and the library appears by itself. Everything chosen here can be changed later in Settings.

### Find your game folders with an AI

Games are often spread over several drives in folders only you know about. Any AI assistant can find them for you:

1. Click **Find my game folders with an AI** (on the setup page, or in Settings › Game folders), then **Copy prompt**.
2. Give the prompt to the assistant you use.
   - An assistant that can run commands on your PC (Claude Code, Codex, GitHub Copilot in a terminal...) looks by itself.
   - A chat assistant (ChatGPT, Claude, Gemini...) gives you one PowerShell command to run, and asks you to paste its output back.
3. Paste the assistant's answer (its list of folders) into the second box and click **Check folders**.
4. Each folder gets a verdict: *Will be scanned*, or why not (not found, on a drive you never read, already found through Steam or the Xbox app, inside another folder in the list, too broad such as `C:\` or `C:\Program Files`, already in your list). Tick the ones you want and click **Add selected folders**.

The prompt tells the assistant which drives it must never open, which folders are already covered, and to only look at folder names without opening, running or changing anything. The assistant's provider sees your folder names, nothing else. Game Hub itself never contacts an AI service.

## The home page

From top to bottom:

| Section | What it shows |
|---|---|
| **Billboard** | One game at a time on its wide background art. It starts on a featured game: the newest install from the last `newDays` days (default 14), otherwise your most recently played game, otherwise the first game. Then, while nothing is picked, it moves through the Game Hub banner and every game in your library, in a new shuffled order each round, one every 2 seconds (*From your library*). Games without wide background art appear on a blurred version of their cover or icon. It holds still while the pointer or controller focus is on the billboard, so **Play** never changes under you, and while a dialog is open, the page is scrolled down or hidden, or Windows is set to reduce animations. With no games yet, it shows the Game Hub banner. Point at a favorite, or move to it with the controller, and the billboard switches to that game (*From your favorites*): its art, logo, launcher, size, last played and play time. It keeps showing it after you move away, so the billboard's **Play** plays the game you were looking at. It has **Play**, **Open folder** and the pen (edit). |
| **Favorites** | Games you starred, on large 16:9 cards, in the order you starred them. Hidden while you have no favorites. |
| **Continue playing** | Up to 15 games, most recently played first. "Played" means launched from the hub, a recorded [play session](#play-time), or the last-played date Steam records. |
| **Most played** | Up to 15 games with the most [play time](#play-time). |
| **Recently added** | The 12 most recent installs. |
| **One row per launcher** | Steam, Epic Games, EA, Ubisoft, GOG, Battle.net, Riot Games, Amazon Games, Rockstar, Xbox and Standalone, for the launchers you have games in. Rows are ordered by how many games you have in each, so no launcher is privileged and standalone games get the same treatment. |
| **Storage** | One card per drive that holds games. See [Storage and Cleanup](#storage-and-cleanup). |
| **Cleanup** | Duplicate installs and leftovers. It appears only when there is something to clean. |

The footer shows the game count, when the last scan ran, and which drives are excluded.

Rows scroll sideways. Use the arrows at the row's edges, a trackpad, or Shift + mouse wheel.

## Game cards

Most rows use 2:3 portrait covers. Favorites use 16:9 cards: the wide background art with the game's logo on top.

Hover a card (or focus it with `Tab`) to show:

- **Name, launcher, play time (or the drive, for a game never played) and size.** Hover longer for a tooltip with the folder, last played date and play time. A ⚠ appears when the game has a warning, for example an Epic game the Epic launcher no longer knows about.
- **▶ Play.** Clicking anywhere on the card, or pressing `Enter`, does the same.
- **☆ Favorite.** Adds the game to Favorites or removes it.
- **📁 Folder.** Opens the install folder in Explorer.
- **✎ Pen** (top-right). Opens the [edit dialog](#editing-a-game).

A white **NEW** tab marks games installed in the last `newDays` days. While a game is starting, its play button spins. A short message confirms the launch, or explains why it failed (for example, *Executable not found*).

## While you play

After you launch a game, Game Hub gets out of the way and comes back when you're done:

1. **The game gets the keyboard, mouse and controller.** As soon as the game opens its window, Game Hub minimizes itself. Windows then hands control to the game straight away, so you don't have to click into it first. Through a launcher this can take a moment: Steam or Epic start first, then the game.
2. **Game Hub comes back when you quit.** A few seconds after the game has fully closed, Game Hub is restored and brought to the front. You can pick the next game, with the mouse or the controller.

Both steps can be turned off in **Settings › While you play**, or with `minimizeOnLaunch` and `restoreAfterGame` in [`config.json`](configuration.md#configjson). Either way, Game Hub keeps watching the game until it closes, to record its [play time](#play-time).

Good to know:

- **App window only.** This works with the Game Hub app window that the Desktop and Start menu shortcuts open (Chrome, or Edge if Chrome isn't installed). A Game Hub tab inside a normal browser window is never minimized, because that would hide your other tabs too.
- **Boot screens.** Many games first show a small boot or splash screen (anti-cheat, launcher, logo), or nothing at all for a while. Game Hub waits for the game's real window, at least 960×540, before it steps aside, so that window is the one that gets focus.
  - A smaller window counts once it has been the game's only window for 30 seconds, so small games work too.
  - If a game shows no window within 90 seconds, Game Hub minimizes anyway, and brings the game's window to the front when it opens.
- **Games that never start.** If nothing starts within 5 minutes, for example because a launcher is waiting for an update or a login, Game Hub stays where it is.
- **Games with their own launcher.** A game whose own launcher stays open after you quit (inside the game's folder) counts as running until that launcher closes too.

## Play time

Game Hub counts how long you play:

- **Games started from Game Hub** are timed from the moment the game's programs appear until they have all closed. Each session (start, end, minutes) is added to `data\sessions.jsonl`; sessions shorter than a minute are ignored.
- **Steam games** also bring their whole history: Steam's own play time is read from its local settings at every scan. For a Steam game, Game Hub shows whichever is larger, Steam's total or its own (Steam counts the sessions Game Hub starts too).
- **Games started elsewhere** (from Steam, a desktop shortcut, the game's own launcher) are counted only if you turn on **Count games started outside Game Hub** in Settings › While you play (`trackOutsideLaunches`). A small background check then looks once a minute at which of your games are running. It is off by default. A session is never counted twice.

Play time appears on the cards, on the billboard (*12 h played*), in the **Most played** row, in the [games list export](#backups), and as the **Most played** sort order.
## Using a controller

Game Hub works with a **DualSense (PS5)**, a **DualShock 4 (PS4)**, an **Xbox** controller, or any controller your browser reports with the standard layout, over USB or Bluetooth. **DS4Windows** works as well.

Press any button to start: the first press only shows where you are, with a white focus frame and a bar of button hints at the bottom right. Then:

| Button (PlayStation / Xbox) | Action |
|---|---|
| D-pad or left stick | Move between cards, rows, tabs and buttons. Hold to repeat. |
| ✕ / A | Play the selected game, or press the selected button |
| ○ / B | Back: close a dialog, clear the search, go to Home, or scroll to the top of Home |
| △ / Y | Add the selected game to Favorites, or remove it |
| □ / X | Edit the selected game (opens the pen dialog) |
| L1 / LB, R1 / RB | Previous / next tab (Home, each launcher, Settings) |
| Share or Create / View | Open the on-screen keyboard to search |
| Options / Menu (≡) | Open or close Settings |
| Right stick | Scroll the page |
| Hold View + Menu (Share + Options through DS4Windows), anywhere in Windows | Bring Game Hub back to the front, or open it |

On Home, the billboard and the Favorites row count as one screen: moving between them, or along the row, keeps the page still so the billboard stays whole. The page scrolls once you move down to the next row. The hints show PlayStation symbols when a PlayStation controller is connected, and Xbox letters otherwise. Move the mouse, click or scroll, and the mouse takes over again.

Good to know:

- **Only while Game Hub is in front.** Presses meant for a game never reach Game Hub, even if its window is visible on another screen. A button you're still holding when Game Hub comes back is ignored, so the press that quit your game can't launch another one.
- **DS4Windows.** It adds a virtual Xbox controller next to your real DualShock 4. Game Hub merges every connected controller into one, so each press counts once. If you hide the real controller with HidHide, Game Hub only sees the Xbox one and shows Xbox letters.
- **A Steam game ignores your controller? Check Steam Input first.** Steam decides how each Steam game sees your controller, and Steam Input can be switched off for a single game. When it's off, a PlayStation controller may not reach that game at all, even though Steam itself shows the controller as connected.
  - **To fix it:** in Steam, open **Library › right-click the game › Properties › Controller**, or the controller icon while the game runs. Turn **Steam Input** on for that game. Depending on your Steam version and language, it's a switch (for example *Use Steam Input compatibility layer*) or an override set to *Enable Steam Input*.
  - **If you use DS4Windows for that game instead,** leave Steam Input off, so the game doesn't see two controllers.
  - Game Hub's **Settings › Controllers** card carries the same reminder.
- **Steam's Desktop Layout.** While Steam is open, it may turn the controller into a mouse outside games, so the stick or touchpad also moves the pointer. If that gets in the way, turn the desktop layout off in Steam's controller settings.
- **The PS / Xbox button** is not used. Windows and Steam reserve it.
- **USB, Bluetooth and DS4Windows all work in Game Hub.** Games are another matter, which is why one game accepts a DualShock 4 over Bluetooth and another only over USB or through DS4Windows. Windows games read controllers in different ways:
  - **XInput:** most PC games. It only understands Xbox controllers, so a PlayStation controller needs DS4Windows (or Steam Input) to pretend to be one.
  - **Direct support for PlayStation controllers:** some games. It sometimes covers only the USB connection.
  - **Steam Input:** Steam games. Steam translates the controller itself, which can clash with DS4Windows.

  Game Hub reads all three kinds of connection through the browser, so it works whichever one a game needs.
- **On-screen keyboard.** Share / View (or ✕ / A on a text field) opens it. Move with the D-pad, ✕ / A types the highlighted key, □ / X deletes, △ / Y adds a space, Options / Menu is *Done* and ○ / B closes it. After a search, *Done* jumps to the first result.
- **Drop-down lists** (sort order, language, DS4Windows choices) can't open from a controller: each press of ✕ / A picks the next choice. **Hide from hub** asks for confirmation in a Windows dialog, which needs the mouse or keyboard.
- **More about controllers in games**, DS4Windows rules per game, and the bring-back shortcut: see [Controllers](controllers.md).

## Browsing and search

The tabs at the top filter by launcher. The page address follows what you see, so you can bookmark any view:

| Address | View |
|---|---|
| `#/` | Home |
| `#/l/steam`, `#/l/epic`, `#/l/ea`, `#/l/ubisoft`, `#/l/gog`, `#/l/battlenet`, `#/l/riot`, `#/l/amazon`, `#/l/rockstar`, `#/l/xbox`, `#/l/other` | One launcher (`other` = Standalone) |
| `#/d/D` | Games on drive D: (clicking a Storage card opens this) |
| `#/all` | Every game |
| `#/settings` | Settings |

**Sort by** (top right of every grid): name, most played, recently played, recently added or size. Your choice is remembered in this browser.

**Search** matches every word you type against the name, launcher, drive and install path. It ignores accents and case. Typing `epic d:` shows Epic games on D:. Sorted by name, games whose names start with your search come first. Press `Enter` to launch the first result, or `Esc` to clear.

## Editing a game

Click the **pen** on a card, or on the billboard.

**Artwork (left side)**

| Control | Effect |
|---|---|
| **Search Steam artwork** | Searches the Steam store, prefilled with the game's name. Click a result to download its cover, background and logo. This replaces any custom images. The choice is remembered (`steamAppId`), so later scans keep it. |
| **Upload cover…** | Uses your own portrait image (JPEG, PNG or WebP, up to 25 MB). You can also drop an image file onto the cover preview. |
| **Upload background…** | Uses your own wide image. It's used by the billboard and the 16:9 Favorites card. |
| **Remove custom cover / background** | Goes back to the downloaded artwork. |

Custom images always win over downloaded ones. See [Artwork](artwork.md).

**Details (right side)**

| Field | Notes |
|---|---|
| **Name** | The display name. Kept across rescans. |
| **Executable** | Type a full path, or click **Browse…** for the Windows file picker. |
| **Launch arguments** | Passed to the executable, for example `-windowed`. Disabled while the game starts through a launcher, since launchers ignore them. |
| **DS4Windows while this game runs** | Only when DS4Windows is installed: keep it on, turn it off, or use one of its profiles while this game runs. The suggestion for this game and its reason are shown below. See [Controllers](controllers.md#ds4windows-rules-per-game). |
| **Install folder** | Read-only. |

How the game starts depends on the executable you choose:

- **Launcher games** (Steam, Epic, Ubisoft, Battle.net, Riot, Amazon, Xbox app) start through their launcher.
- **Picking an executable** makes the hub start that file directly instead.
- **To undo it**, use the link under the field: *Start through Steam again*, or *Use the detected executable again* for games without a launcher.

Saving a new executable triggers a short background rescan to refresh the game's icon.

**Hide from hub** removes the game from every view. Bring it back from **Settings › Hidden games**. For games you added yourself, the button reads **Remove from hub** and deletes the entry instead.

## Adding a game

Use this for anything the scan missed: an emulator, a game on an unusual path, a tool you want next to your games.

1. Go to **Settings › Library › Add a game**.
2. Click **Browse…** and pick the `.exe`. The name is guessed from the file name.
3. Fix the name, and add launch arguments if needed. Click **Add game**.

The game joins the **Standalone** row. Its cover is looked up automatically, and you can change it with the pen.

If the executable is inside a folder the hub already knows as a game, the hub refuses to add it. Edit that game's executable instead. Executables on excluded drives are refused too.

## Settings

The **⚙** icon at the top right opens Settings.

| Card | What it does |
|---|---|
| **Library** | **Rescan now** re-runs the scan and cover lookup. **Add a game** adds one by hand. **Fetch missing covers** retries artwork for games that have none. It shows how many games have a cover. |
| **Game folders** | Folders whose sub-folders are games, one game per sub-folder. **Add folder…** opens the Windows folder picker, **Find my game folders with an AI** opens the [AI helper](#find-your-game-folders-with-an-ai), and **Remove** drops a folder. Changes trigger a rescan. Folders on never-read drives can't be added. |
| **Drives** | Every drive, with a **Never read** switch. Never-read drives are not scanned, and their games, folders and executables are refused. **Save and rescan** applies the change. Drives excluded by name (`excludeVolumeLabels` in `config.json`) are listed under the switches. |
| **Hidden games** | Games you hid, each with **Show again**. |
| **While you play** | **Minimize Game Hub when a game starts** and **Bring Game Hub back when you quit** (both on by default; see [While you play](#while-you-play)), and **Count games started outside Game Hub** (off by default; see [Play time](#play-time)). |
| **Controllers** | The controller buttons, **Bring Game Hub back with the controller** (on by default), what to check when a Steam game ignores your controller, and, when DS4Windows is installed, its rules per game with a suggestion for each game (**Check my games**, **Use the suggestions**, **Tell Game Hub**). See [Controllers](controllers.md#which-games-need-ds4windows). |
| **Language** | Automatic (your browser's language) or one of 11 languages. The non-English ones were translated by an AI; a link lets you report a wrong translation. See [Translating](translating.md). |
| **Security** | Only on a PC with other Windows accounts: **Lock Game Hub to my Windows account**. See [SECURITY.md](../SECURITY.md#optional-lock-to-your-windows-account). |
| **Backups** | Your Game Hub backups with **Restore**, **Back up now**, a second folder to copy backups to, and **Download my games list (CSV)**. It also shows your [data folder](installation.md#where-your-data-lives). See [Backups](#backups). |
| **Startup** | Start the server with Windows. This toggles the Startup-folder shortcut. |
| **Made by** | Who made Game Hub, with links to their website and the GitHub project, **Star on GitHub**, **Give feedback**, **Report a problem**, and the version. The details come from [`www/brand/about.json`](../www/brand/README.md). |

Steam, Epic, Ubisoft, GOG, Battle.net, Riot, Amazon, Rockstar and Xbox app games are found through their launchers wherever they are installed. So are most EA games, through their Windows uninstall entries. Add a game folder for everything else, including games a launcher forgot (the setup page suggests the launchers' own folders for that). See [Launchers](launchers.md).

Everything else lives in [`config.json` and `overrides.json`](configuration.md).

## Backups

Game Hub backs up **its own data**, not your games:

- **What:** `config.json`, `overrides.json` (your fixes, hidden games, custom names and executables), the game list with every game's folder, favorites and launch dates, play time, the game window titles it learned, and your custom covers. Each backup also holds a `my-games.csv`.
- **Not included:** game files and game saves. Use your launchers' cloud saves for those.
- **When:** once a day (checked at startup and every 6 hours), only when something changed. **Back up now** makes one at once.
- **Where:** `data\backups\gamehub-<date>_<time>.zip`. Game Hub keeps every backup of the last 48 hours (up to 20), then one per day for 7 days and one per week for 4 weeks. **Also copy backups to** puts a copy of each new backup in another folder, for example a cloud-synced folder or a second drive.
- **Restore** puts a backup's files back and reloads the page. Your current state is backed up first (*before a restore*), so a restore can be undone.
- **Self-repair:** if a crash or a power cut leaves your settings, fixes, game list or favorites empty or unreadable, Game Hub puts back the newest good copy when it starts, and a banner on the page says which file was repaired.
- **Download my games list (CSV)** gives you a spreadsheet of every game: name, launcher, drive, folder, how it starts, size, hours played, last played and whether it is a favorite. Handy when you reinstall Windows: it tells you where everything was.

## Storage and Cleanup
**Storage** shows a card per drive that holds games:

- the drive letter, label and number of games;
- a bar of space used by games (white), other files (grey) and free space;
- the totals.

Click a card to list that drive's games.

**Cleanup** collects two kinds of items:

- **Duplicates.** A game you marked with `duplicateOf` in `overrides.json`, meaning a second install of a game you keep elsewhere. Duplicates are left out of every row, the search and the game count. They appear only here.
- **Leftovers.** Folders you listed under `cleanup` in `overrides.json`, such as an abandoned download or an installer archive.

Each item shows its size, which copy to keep, your note, and **Open folder**. **Game Hub never deletes anything.** Check the folder, then uninstall it through its launcher or delete it yourself.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `/` or `Ctrl+K` | Focus search |
| `Enter` (in search) | Launch the first result |
| `Esc` (in search) | Clear the search |
| `Tab` / `Shift+Tab` | Move between cards and buttons |
| `Enter` or `Space` (on a card) | Launch the game |
| `F5` | Reload the page (after changing a file by hand) |

For controller buttons, see [Using a controller](#using-a-controller).
