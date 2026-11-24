# Set up your library

From a fresh download to every game in one place, with the right names, covers and launcher links, and no duplicates. It takes about 15 minutes for a typical library.

> **Two ways to do this.**
>
> - **With an AI assistant:** it asks questions, runs or gives you the commands, and does the tedious parts. See [Set up with an AI assistant](setup-with-ai.md).
> - **By hand:** follow the steps below. Everything is done in the hub and with Notepad.

1. [Install](#1-install)
2. [The setup page: drives and folders](#2-the-setup-page-drives-and-folders)
3. [First scan](#3-first-scan)
4. [Review the library](#4-review-the-library)
5. [Link launcher games](#5-link-launcher-games)
6. [Sort out duplicates](#6-sort-out-duplicates)
7. [Fix covers](#7-fix-covers)
8. [Test, and keep it tidy](#8-test-and-keep-it-tidy)

## 1. Install

Follow [Installation](installation.md#install) up to and including **Create the shortcuts**, then open **Game Hub** from the Desktop or Start menu. With no library yet, it shows the setup page. Nothing is scanned until you finish it.

## 2. The setup page: drives and folders

**Step 1: drives that must never be read.** Removable drives, backup disks, anything private. Game Hub only scans fixed drives, but many USB SSDs count as fixed, so the setup page ticks every USB drive for you. Tick any other drive Game Hub must stay away from. On this page Game Hub only reads each drive's name, size and type.

**Step 2: where your games are.**

- Steam and Xbox app games are found through their launchers wherever they are. Their folders are listed at the top, with nothing to do.
- The folders of the other launchers (Epic, EA, Ubisoft, GOG, Battle.net) are suggested and ticked. Their games are found through the launcher too, but scanning the folder also finds games the launcher has forgotten, for example after a reinstall.
- Everything else lives in **game folders**: folders where *each sub-folder is one game*, such as `D:\Games`. Folders whose name looks like that are suggested. Untick anything that isn't a game folder.
- **Add folder...** adds another one. You can add a whole drive (`E:\`): every top-level folder on it then counts as a game, so afterwards list the non-game ones under `ignore` in `config.json` (see [Configuration](configuration.md#configjson)).
- **Not sure where your games are?** Click **Find my game folders with an AI**, copy the prompt into the AI assistant you use, and paste its answer back. Game Hub checks every folder in the answer and only lets you add the ones that make sense. See [Find your game folders with an AI](usage.md#find-your-game-folders-with-an-ai).

**Step 3: options.** Start with Windows, minimize Game Hub while you play and bring it back afterwards, and the language. On a PC with other Windows accounts you can also lock Game Hub to yours.

Everything chosen here can be changed later in **Settings › Drives**, **Settings › Game folders** and the other Settings cards.

## 3. First scan

Click **Scan my games**. The scan runs, then the cover download, and the library appears by itself, usually within a minute or two.
## 4. Review the library

Go through the home page and **All games** (`#/all`), and fix what's wrong. Every fix survives future rescans.

| What you see | Fix |
|---|---|
| A game is missing | <ul><li>Is its parent folder a game folder? If not, add it in **Settings › Game folders › Add folder…**.</li><li>Or add just that game: **Settings › Add a game**, then pick its `.exe`.</li><li>Still missing? See [Troubleshooting › A game is missing](troubleshooting.md#a-game-is-missing).</li></ul> |
| Something that isn't a game (a tool, a launcher, a benchmark) | Pen › **Hide from hub**. To skip a whole folder, add it to `ignore` in `config.json`. |
| Wrong name | Pen › **Name**. |
| Starts the wrong program, or does nothing | Pen › **Executable › Browse…**, then pick the game's real `.exe`. Usually it's the largest one named after the game, not `setup`, `uninstall`, `crash…` or `redist`. Add **Launch arguments** if the game needs them. |
| ⚠ on a card | Hover it to read the warning. Most are about launcher linking: see the next step. |

**Bypassing a launcher is a trade-off.** For Steam, Epic, Ubisoft, Battle.net, Riot, Amazon and Xbox app games, choosing an executable skips the launcher, and with it cloud saves, updates and the overlay. Do it only when the launcher link doesn't work. The link under the executable field undoes it.

## 5. Link launcher games

Game Hub starts launcher games through their launcher. The launcher has to know the game, or the game has to start without it.

| Launcher | What to do |
|---|---|
| **Steam** | Nothing, usually. If a game's folder exists under `steamapps\common` but Steam says *not installed*, click **Install** in Steam and pick that library. Steam finds the files and verifies them instead of downloading. For a library on another drive, use **Steam › Settings › Storage › Add drive**. |
| **Epic** | Games marked ⚠ *Not registered in the Epic launcher* start directly from their executable, which works for most. If a game insists on Epic, re-link it: in the Epic launcher, go to **Library › the game › Install**. As the install location, choose the folder **above** the game's folder. For a game in `F:\Games\HogwartsLegacy`, choose `F:\Games`. Epic adds its own folder name and, if it matches, verifies the files instead of downloading. If it starts downloading the whole game, cancel it: the folder name doesn't match Epic's. Rescan afterwards. The game then starts through Epic. |
| **EA app** | Nothing for launching: the hub starts the game, and the game opens the EA app itself. If you want the EA app to list it too, use the EA app's option to locate an existing installation, if it offers one. |
| **Ubisoft Connect** | Nothing, usually. If Ubisoft Connect says *not installed*, its game page offers **Locate installed game**. |
| **GOG Galaxy, Rockstar** | Nothing. They start from their executable (GOG games with GOG's own launch parameters). |
| **Battle.net, Riot, Amazon Games** | Nothing, usually. They start through their launcher, which must be installed and signed in. |
| **Xbox app (Microsoft Store, PC Game Pass)** | Nothing. They start through Windows, like from the Start menu. Most of them only run that way, so leave their executable alone. |
| **DRM-free, emulators** | Nothing. They start from their executable. |

## 6. Sort out duplicates

After a launcher reinstall, or a game bought on two stores, the same game can be installed twice, sometimes on different drives. Look through **All games** for the same title appearing twice. Watch for demos and prologues next to the full game, too.

**Which copy do you actually play?** Strongest evidence first:

1. **What you remember**, and which launcher you use for it.
2. **Last played and play time.** The hub's *Continue playing* and *Most played* rows, and the card tooltips, show games launched from the hub plus Steam's own play history.
3. **The launcher.** Steam, Epic, EA and Ubisoft show the last-played date or play time on the game's page.
4. **The newest files inside each copy.** Open both folders in Explorer, switch to *Details* view, and sort by **Date modified**. Saves, settings and logs change when you play. This is weak evidence on its own, because updates change files too.

**Mark the copy you don't use.**

1. Find both games' ids. Open `data\games.json` in Notepad and search for the game's name: its `"id"` is on the line just above.
2. Create or open `overrides.json`, and add an entry for the copy you don't use. If the file already has a `"games"` section, add the entry inside it, separated from the others by a comma.

   ```json
   {
     "games": {
       "steam-1234560": {
         "duplicateOf": "other-mygame",
         "note": "Steam copy never launched; I play the D: copy."
       }
     }
   }
   ```

   `steam-1234560` is the copy you don't use, and `other-mygame` is the copy you keep.
3. Press **Settings › Rescan now**.

The extra copy then disappears from your library and shows up in the **Cleanup** panel at the bottom of the home page, with its size and folder. Game Hub never deletes anything. To get the space back, uninstall that copy through its launcher, or delete the folder yourself once you're sure.

Leftovers that aren't games, like an abandoned download or an installer archive, can be listed in Cleanup too. See [`cleanup` in Configuration](configuration.md#cleanup).

## 7. Fix covers

| Problem | Fix |
|---|---|
| Wrong cover | Pen › **Search Steam artwork**, and pick the right game. |
| No cover | Pen › **Search Steam artwork** or **Upload cover…**. You can also drop an image file onto the cover in the edit dialog. |
| Microsoft Store game | Add `"msStoreId": "9NBLGGH2JHXJ"` (the 12-character code from the game's Microsoft Store web address) to the game in `overrides.json`, then **Settings › Fetch missing covers**. |
| Wide background for the banner and Favorites | Pen › **Upload background…** |

Details: [Artwork](artwork.md).

## 8. Test, and keep it tidy

**Test.** Launch one game from each launcher you use: click its card. Fix anything that doesn't start (step 4 or 5). Once a game's window opens, Game Hub minimizes so the game gets your keyboard, mouse and controller. When you quit, it comes back. You can change both in **Settings › While you play**.

**Playing with a controller?** Game Hub itself works with a DualSense, a DualShock 4 (also through DS4Windows) or an Xbox controller; see [Using a controller](usage.md#using-a-controller). For **Steam games**, check that **Steam Input** is on for each game you play with a PlayStation controller: Steam › Library › right-click the game › Properties › Controller. If it's off, Steam shows the controller as connected, but the game ignores it. If you use DS4Windows for a game, leave Steam Input off for that game instead. **Using DS4Windows** and tired of quitting it for some games? Set a rule per game in **Settings › Controllers**. Everything about controllers: [Controllers](controllers.md).

**Make it yours.** Star your favorites (☆ on a card): they get a row of large cards at the top of the home page.

**After that:**

- **Installed or moved a game?** Use **Settings › Rescan now**.
- **Want the hub ready at logon?** Leave **Settings › Startup** on.
- **Moving to a new PC, or reinstalling?** Game Hub backs itself up every day: settings, fixes, favorites, play time and custom covers (**Settings › Backups**). Copy the newest `data\backups\gamehub-….zip` somewhere safe, or set **Also copy backups to** a second drive or a synced folder. On the new PC, install Game Hub and finish the setup page, then put the zip in `data\backups`, restore it from **Settings › Backups** and click **Rescan now**. **Download my games list (CSV)** tells you where every game was installed.
- **Worried about something a download did?** See [Staying safe](staying-safe.md).
