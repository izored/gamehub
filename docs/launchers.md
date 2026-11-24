# Launchers

How Game Hub finds the games of each launcher and how it starts them. The scanner is [`scan-games.ps1`](../scan-games.ps1); launching happens in [`server.ps1`](../server.ps1) (`/api/launch`).

- [Scan order](#scan-order)
- [Steam](#steam)
- [Epic Games](#epic-games)
- [EA app / Origin](#ea-app--origin)
- [Ubisoft Connect](#ubisoft-connect)
- [GOG Galaxy](#gog-galaxy)
- [Battle.net](#battlenet)
- [Riot Client](#riot-client)
- [Amazon Games](#amazon-games)
- [Rockstar Games Launcher](#rockstar-games-launcher)
- [Xbox app (Microsoft Store, PC Game Pass)](#xbox-app-microsoft-store-pc-game-pass)
- [Standalone games](#standalone-games)
- [How the executable is chosen](#how-the-executable-is-chosen)
- [How the name is chosen](#how-the-name-is-chosen)
- [Not supported (yet)](#not-supported-yet)

## Scan order

Sources run in this order. **The first one to claim an install folder wins.** A folder inside an already-claimed folder is skipped, and so is a folder that contains one.

1. Steam app manifests
2. Epic launcher manifests
3. Ubisoft Connect registry
4. GOG Galaxy registry
5. Battle.net (Blizzard uninstall entries)
6. Riot Client
7. Amazon Games (uninstall entries)
8. Rockstar Games Launcher registry
9. Xbox app packages
10. Game folders (`gameRoots`): every sub-folder
11. Discovery: uninstall-registry install folders, then `discoverRoots` sub-folders, keeping only those with engine files
12. Manual additions (`overrides.json › add`)

A game installed by Steam is always listed as a Steam game, even if it sits inside one of your game folders.

## Steam

| | |
|---|---|
| Found through | `HKCU\Software\Valve\Steam › SteamPath`, then every library in `steamapps\libraryfolders.vdf`, then each `appmanifest_<appid>.acf` |
| Launched with | `steam://rungameid/<appid>` |
| Id | `steam-<appid>` |
| Extras | Size on disk, last-played time, play time (from `userdata\<account>\config\localconfig.vdf`; the largest figure across the PC's Steam accounts), and artwork from Steam's local library cache |

Skipped:

- Steamworks Common Redistributables (app 228980) and anything named *Redistributable*, *Steamworks*, *Proton* or *Steam Linux Runtime*;
- libraries on excluded drives;
- manifests whose folder is missing, listed in `skipped[]`.

## Epic Games

| | |
|---|---|
| Found through | `%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests\*.item` |
| Launched with | `com.epicgames.launcher://apps/<namespace>%3A<catalogItemId>%3A<appName>?action=launch&silent=true` |
| Id | `epic-<install-folder-name>` |

Incomplete installs and DLC manifests are skipped.

**Games the Epic launcher forgot.** If the launcher was reinstalled or lost its manifests, its games are still on disk but no longer registered. Game Hub still finds them if their folder is under a game folder or discoverable, because Epic installs contain an `.egstore` folder. These games:

- are listed under **Epic Games**;
- start **directly from their executable**;
- carry a warning on their card.

Most work this way. Games that require the Epic launcher to be running and signed in may ask you to re-link them:

1. In the Epic launcher, open **Library**, click the game, and choose **Install**.
2. As the install location, choose the folder **above** the game's folder. For `F:\Games\HogwartsLegacy`, choose `F:\Games`.

Epic adds its own folder name. If that matches, it verifies the files instead of downloading them again. If it starts downloading the whole game, cancel it: the existing folder's name differs from Epic's. After re-linking, rescan. The game then starts through Epic.

## EA app / Origin

| | |
|---|---|
| Found through | Game folders or discovery. A folder is EA when it contains `__Installer\installerdata.xml`, or its uninstall entry's publisher is Electronic Arts. |
| Launched with | The executable named in `installerdata.xml` (`<filePath>`). Full versions are preferred over trial executables. |
| Id | `ea-<install-folder-name>` |

EA games are started directly. The game itself brings up the EA app if it needs it.

EA games normally have an uninstall entry, so discovery finds them wherever they are, as long as their folder contains engine files.

`origin2://` links are allowed if you set one yourself as a `uri` override.

## Ubisoft Connect

| | |
|---|---|
| Found through | `HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\<id> › InstallDir` |
| Launched with | `uplay://launch/<id>/0` |
| Id | `ubi-<id>` |
| Name | From the game's uninstall entry, otherwise the folder name |

## GOG Galaxy

| | |
|---|---|
| Found through | `HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\<id>` (`path`, `exe`, `launchParam`, `gameName`) |
| Launched with | The game's executable from the registry, with GOG's `launchParam` as arguments |
| Id | `gog-<GOG game id>` |

GOG games have no DRM, so they start without GOG Galaxy. Galaxy's play-time tracking and cloud saves only apply when you start them from Galaxy.

## Battle.net

| | |
|---|---|
| Found through | Windows uninstall entries published by *Blizzard Entertainment* (the Battle.net app itself is left out) |
| Launched with | `battlenet://<code>` for the games whose Battle.net code is known: Overwatch 2 (`Pro`), Diablo IV (`Fen`), World of Warcraft (`WoW`) and Classic (`WoWC`), Diablo III (`D3`), Hearthstone (`WTCG`), Heroes of the Storm (`Hero`), StarCraft II (`S2`), StarCraft Remastered (`S1`), Warcraft III (`W3`), Diablo II: Resurrected (`OSI`). Other Blizzard games start from their executable. |
| Id | `bnet-<Blizzard uid>` |

The Battle.net app must be installed and signed in. It opens on the game, which then starts as usual.

## Riot Client

| | |
|---|---|
| Found through | `%ProgramData%\Riot Games\RiotClientInstalls.json` (where the Riot Client is) and `%ProgramData%\Riot Games\Metadata\<product>.<patchline>\*.product_settings.yaml` (each game's folder) |
| Launched with | `RiotClientServices.exe --launch-product=<product> --launch-patchline=<patchline>` |
| Id | `riot-<product>`, for example `riot-league_of_legends`, `riot-valorant` |

The Riot Client must be installed and signed in.

## Amazon Games

| | |
|---|---|
| Found through | Windows uninstall entries that uninstall through *Amazon Game Remover* |
| Launched with | `amazon-games://play/<product id>` |
| Id | `amazon-<name>` |

## Rockstar Games Launcher

| | |
|---|---|
| Found through | `HKLM\SOFTWARE\WOW6432Node\Rockstar Games\<game> › InstallFolder` (the launcher and Social Club entries are left out) |
| Launched with | The game's executable, which hands over to the Rockstar Games Launcher itself |
| Id | `rockstar-<name>` |

Rockstar games bought on Steam or Epic are listed under those launchers instead.

## Xbox app (Microsoft Store, PC Game Pass)

| | |
|---|---|
| Found through | Installed app packages (`Get-AppxPackage`) that contain a `MicrosoftGame.config`, the file every PC game from the Xbox app has |
| Launched with | `shell:AppsFolder\<package family name>!<app id>`, started through Windows Explorer, exactly like the Start menu does |
| Id | `xbox-<name>` |
| Extras | The Microsoft Store id from `MicrosoftGame.config`, used to find the cover art |

Most of these games only run when started that way, so leave their executable alone. Their folder (`XboxGames` on each drive by default) is covered automatically and never needs to be a game folder.

## Standalone games

Everything else is listed as **Standalone**: DRM-free games, itch.io downloads, emulators, games installed from discs. Game Hub finds them in two ways:

- **Game folders:** every sub-folder of a `gameRoots` entry.
- **Discovery:** install folders from the Windows uninstall list, and sub-folders of `discoverRoots`. Discovery needs evidence that the folder is a game:
  - `steam_api(64).dll`, `UnityPlayer.dll`, `GameAssembly.dll`, EOS SDK, Bink, FMOD, DLSS/XeSS/Streamline, AMD AGS, GOG Galaxy, Ubisoft or Discord game SDK, or PhysX libraries; or
  - an Unreal `Paks` folder with `.pak` files; or
  - an `EasyAntiCheat` or `BattlEye` folder.

  Known non-game vendors are excluded from discovery: Microsoft, NVIDIA, Adobe, audio software, launchers' own folders and so on.

Standalone games start from their executable. Launch arguments from the edit dialog are passed along, and the working directory is the executable's folder.

## How the executable is chosen

For folders without a launcher link, and as the fallback "detected executable":

1. **EA installer data.** Use the `<filePath>` from `__Installer\installerdata.xml` if present.
2. **Otherwise, list candidates:** every `.exe` up to 4 levels deep that is at least 100 KB. The following are left out:
   - installers, uninstallers, redistributables;
   - crash reporters, anti-cheat services, updaters, overlays, launchers' helpers;
   - anything inside folders like `_CommonRedist`, `__Installer`, `Engine`, `Support`, `DirectX`, `EasyAntiCheat`.
3. **Rank the candidates:**
   1. fewest folders deep;
   2. file name closest to the game's name;
   3. largest file.

When a game has several executables, it usually picks the main one. When it picks wrong, set the right one with the pen (or `exe` in `overrides.json`).

## How the name is chosen

The first of these that exists:

1. your `name` override;
2. the launcher's name (Steam manifest, Epic display name);
3. the Windows uninstall entry;
4. the executable's *Product name*, unless it's generic (*Unreal*, *Unity*, *Game*, *Launcher*…);
5. the folder name, with `CamelCase` split into words.

Trademark symbols and trailing version numbers (`v1.2.3`, `version 4`) are removed.

## Not supported (yet)

These launchers have no native integration. Their games show up as **Standalone** if they're in a game folder or discoverable, and start from their executable. Some may refuse to start without their launcher.

- itch app
- Legacy Games, Humble App, and other smaller stores
- Older Microsoft Store games without a `MicrosoftGame.config` (most are apps rather than games)

Adding a launcher means three things: a scanner section that reads its install records, a launch method, and its URI scheme in the server's allowlist. See [CONTRIBUTING.md](../CONTRIBUTING.md#adding-a-launcher).
