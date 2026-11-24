# Controllers

Game Hub works with a mouse, a keyboard or a controller. This page explains how to use a controller in Game Hub itself, and how to get each kind of controller working in your games: Xbox, DualSense (PS5) and DualShock 4 (PS4).

- [In Game Hub](#in-game-hub)
- [Bring Game Hub back with the controller](#bring-game-hub-back-with-the-controller)
- [In your games: who talks to the controller](#in-your-games-who-talks-to-the-controller)
- [Which setup for which controller](#which-setup-for-which-controller)
- [DS4Windows rules per game](#ds4windows-rules-per-game)
- [Which games need DS4Windows?](#which-games-need-ds4windows)
- [Every button pressed twice? (double input)](#every-button-pressed-twice-double-input)
- [USB or Bluetooth](#usb-or-bluetooth)
- [Troubleshooting](#troubleshooting)

## In Game Hub

Any controller the browser recognises works: DualSense, DualShock 4 (directly or through DS4Windows) and Xbox controllers, plus most pads that behave like an Xbox controller. If you have two controllers connected, or Windows sees one controller twice (DS4Windows does that), Game Hub treats them as one.

| Button (PlayStation / Xbox) | What it does |
|---|---|
| D-pad or left stick | Move between games and buttons |
| Right stick | Scroll the page |
| Cross / A | Play the selected game, or press the selected button |
| Circle / B | Back: close a window, clear the search, go to the home page, then to the top |
| Triangle / Y | Add the selected game to Favorites, or remove it |
| Square / X | Edit the selected game (cover, name, executable) |
| L1 / R1, LB / RB | Previous or next tab (Home, each launcher, Settings) |
| Share or Create / View | Open the on-screen keyboard to search |
| Options / Menu | Open Settings, or go back home from Settings |

Button hints at the bottom right show what each button does at that moment. Game Hub listens to the controller only while its window is in front, so presses meant for a game never reach it. The first press after you used the mouse only shows where you are.

**On-screen keyboard.** Share / View opens it for the search box (or for the text field you are on, in a window such as Edit). Move with the D-pad, Cross / A types the highlighted key, Square / X deletes, Triangle / Y adds a space, Options / Menu is Done and Circle / B closes the keyboard. After a search, Done jumps to the first result.

**Drop-down lists** (sort order, language, DS4Windows choices) cannot open from a controller: each press of Cross / A picks the next choice.

## Bring Game Hub back with the controller

Hold **View + Menu** on an Xbox controller (**Share + Options** on a PlayStation controller through DS4Windows) for 1.5 seconds, anywhere in Windows. Game Hub comes to the front, or opens if it was closed. Handy when a game minimized it, or when you closed a game from its own menu and landed on the desktop.

- It is on by default. Turn it off in **Settings › Controllers**.
- A small background helper (`controller-helper.ps1`) reads controllers through XInput, the Windows system that Xbox controllers use. It checks every 1.5 seconds when no controller is connected and costs nothing noticeable.
- XInput sees Xbox controllers and anything that pretends to be one: a PlayStation controller **through DS4Windows**, or through Steam while Steam is open. A DualSense or DualShock 4 connected **directly**, with neither, is not seen, so the shortcut does nothing for it. Game Hub's own controller support (the table above) still works.

## In your games: who talks to the controller

A game can see your controller in one of three ways. Problems almost always come from two of them working at once, or from none of them.

1. **The game itself.** Every PC game with controller support understands Xbox controllers. Many recent games also understand PlayStation controllers natively; some use the DualSense's haptics and adaptive triggers, often over USB only.
2. **Steam Input.** Steam translates your controller for each game it launches. It is set **per game**, and can be switched off for one game without you noticing. In Steam: Library › right-click the game › Properties › Controller (or the controller icon while the game runs), then choose to turn Steam Input on or off for that game. The global settings are in Steam › Settings › Controller.
3. **DS4Windows.** A free tool that makes a PlayStation controller look like an Xbox controller to every game, Steam or not. It needs the companion driver **HidHide** to hide the real controller, otherwise games see both.

> **Controller not working in one Steam game when it works everywhere else?** Check that game's Steam Input setting first. It is the most common cause, and it is easy to miss because it is per game.

## Which setup for which controller

| Controller | Steam games | Other games (Epic, EA, Ubisoft, Xbox app, standalone) |
|---|---|---|
| **Xbox** (and XInput pads) | Works. Steam Input optional. | Works. Nothing to install. |
| **DualSense / DualShock 4** | Steam Input on for the game (or native support if the game has it). | Native support if the game has it. Otherwise DS4Windows, or add the game to Steam as a non-Steam game so Steam Input can handle it. |
| **DualSense / DualShock 4 with DS4Windows running** | Steam Input **off** for that game, or turn DS4Windows off for it (see below). | Works through DS4Windows. For games with native PlayStation support, you may prefer turning DS4Windows off while they run. |

## DS4Windows rules per game

If you use DS4Windows, you have probably had to quit it before playing one game and start it again for another. Game Hub can do that for you, per game, using DS4Windows' own **Auto Profiles** feature. Each game also shows a suggestion: see [Which games need DS4Windows?](#which-games-need-ds4windows)

**Where:** Settings › Controllers › *DS4Windows: per-game rules* (only shown when DS4Windows is installed), or in each game's Edit window (pen icon) under *DS4Windows while this game runs*.

| Choice | What happens while the game is in front |
|---|---|
| Keep DS4Windows on | Nothing changes (the default). |
| Turn DS4Windows off | DS4Windows stops, so the game or Steam Input sees your real PlayStation controller. It starts again as soon as the game is no longer in front: when you quit, or when you switch to another window. |
| Use profile: *name* | DS4Windows loads that profile for the game (for example a profile with different button mappings or lightbar), and goes back to your default profile afterwards. |

Click **Apply to DS4Windows**. Game Hub then:

1. Writes the rules into DS4Windows' `Auto Profiles.xml`, in `%APPDATA%\DS4Windows` (or next to `DS4Windows.exe` for a portable copy).
2. Matches each game by its **install folder**, so any program inside it counts, including launchers and helper programs the game starts. Games protected by anti-cheat can hide their program from DS4Windows, so Game Hub also adds a rule matching the **game window's title**, once the game has been started from Game Hub at least once (that is when Game Hub learns the title).
3. Touches only the rules it wrote itself. Rules you made in DS4Windows stay as they are. A copy of the previous file is kept in `data\backups` (`ds4windows-auto-profiles-<date>.xml`).
4. Restarts DS4Windows if it is running, because DS4Windows reads these rules only when it starts. If it is not running, the rules apply next time it starts.

To undo everything, set every game back to *Keep DS4Windows on* and apply again.

## Which games need DS4Windows?

A game must see your controller once. **Settings › Controllers** suggests, for every game, whether DS4Windows should stay on or turn off while it runs, and says why.

| The game... | DS4Windows | Why |
|---|---|---|
| reads your PlayStation controller by itself | Off | Otherwise the game sees it twice: the real one and DS4Windows' Xbox one. |
| only understands Xbox controllers | On | DS4Windows makes your controller look like one. |
| is a Steam game with Steam Input on | Off | Steam already translates the controller. |

**It depends on the controller and how it's connected,** not only on the game. Many games read a DualShock 4 only with a USB cable, but a DualSense over Bluetooth too. That's why a game can show *Depends on the controller*.

**Your controllers.** At the top, Game Hub lists the PlayStation controllers Windows knows: connected now, paired over Bluetooth, or seen before. Change the connection if you usually plug a controller in another way, or choose *Not used*.

**Where the answers come from,** most trusted first:

1. **You.** After you play a game started from Game Hub whose suggestion is unsure, Game Hub asks once how the controller worked. **Tell Game Hub**, next to any game, does the same at any time: *it works with DS4Windows off*, *it works only with DS4Windows on*, or *buttons press twice with DS4Windows on*. Your answer always wins. **Forget my answer** removes it.
2. **PCGamingWiki,** a community wiki that records, for each PC game, whether PlayStation controllers work, which models, and over USB or Bluetooth.
3. **Steam's store,** whose *DualShock / DualSense Controller Support* labels are set by the publishers.
4. **The game folder.** Sony's own controller library (`libScePad.dll`) means the game reads PlayStation controllers itself.
5. **Steam's own settings,** which say whether Steam Input is forced on or off for each Steam game.

Sources 2 to 4 need **Check my games**. Game Hub looks the games up only when you press it, and sends game names and Steam app numbers, nothing else. It takes about a minute for 30 games. Results are kept for 30 days, and **Check again** looks everything up again. The wiki and the store labels can be wrong or out of date; that is what your answers are for.

**Reading a suggestion:**

- *Suggested*: the sources are clear.
- *Probably*: a reasonable guess, for example when the wiki doesn't say whether Bluetooth works.
- *Depends on the controller*: one of your controllers needs DS4Windows in that game and another doesn't. Choose for the controller you use there, or see the tip below.
- *Not sure: try it*: nothing is known yet. Play once and answer the question.
- *No rule needed*: DS4Windows doesn't handle any of your controllers.

A suggestion that differs from the current choice is highlighted. **Use the suggestions** copies every *Suggested* and *Probably* choice into the list. Nothing changes in DS4Windows until you press **Apply to DS4Windows**.

**Fewer rules: leave the DualSense to the games.** DS4Windows takes over a DualSense too, unless you tell it not to. Most games and Steam understand a DualSense by themselves, so with DS4Windows handling only the DualShock 4, far fewer games need a rule. In DS4Windows, open **Settings**, then **Device Options**, and untick **Enable** under DualSense. Game Hub shows this tip when it applies, and never changes DS4Windows' settings itself.

**With HidHide** (DS4Windows' *Hide DS4 Controller* setting), games never see the real controller, so DS4Windows can stay on everywhere. Turn it off only for games where you want PlayStation buttons and effects.

## Every button pressed twice? (double input)

Symptoms: the game shows two controllers, a press counts twice, the camera spins, or the game shows the wrong button prompts.

Cause: two translators are active at once. Use **one** per game:

- DS4Windows running **and** Steam Input on for the same game: turn Steam Input off for that game, or set the game to *Turn DS4Windows off* in Game Hub.
- DS4Windows without HidHide: install HidHide (DS4Windows offers it in its settings) so games stop seeing the real controller next to the virtual Xbox one.
- Several remapping tools at once (for example DS4Windows plus another DualSense tool): keep only one running.

## USB or Bluetooth

- **DualSense:** haptics and adaptive triggers in PC games usually need a USB cable. Over Bluetooth it works as a normal controller. To pair it, hold PS + Create until the light bar flashes, then add it in Windows Settings › Bluetooth & devices.
- **DualShock 4:** works over USB or Bluetooth (pair with PS + Share).
- **Xbox:** recent controllers pair over Bluetooth; older ones need a cable or the Xbox Wireless Adapter.
- If a Bluetooth controller lags or disconnects, try a cable first: it rules out most wireless problems.

## Troubleshooting

| Problem | What to try |
|---|---|
| Game Hub does not react to the controller | Click the Game Hub window once so it is in front, then press any button: browsers only report a controller after a button press. |
| "The browser does not recognise its button layout" | The controller does not use the standard layout. Use it through DS4Windows or Steam, which present it as an Xbox controller. |
| View + Menu does nothing | Check Settings › Controllers. A PlayStation controller needs DS4Windows (or Steam open) for this shortcut. `logs\watch.log` shows `controller: started` when the helper runs. |
| A game ignores the controller | See [who talks to the controller](#in-your-games-who-talks-to-the-controller): check Steam Input for that game, then DS4Windows. |
| A DS4Windows rule does not trigger | Start the game once from Game Hub so it learns the window title, then apply the rules again. Check that DS4Windows is running. |
| A suggestion is wrong | Use **Tell Game Hub** on that game: your answer replaces the suggestion. If the source says *PCGamingWiki (another title)*, Game Hub matched the wrong wiki page: pick the right Steam artwork for the game (pen › Search Steam artwork), which also tells Game Hub its Steam app, then **Check again**. |
| Check my games finds nothing | It needs the internet. `logs\scan.log` has a line starting with `controllers:` for each game it could not look up. |

More problems and where the logs are: [Troubleshooting](troubleshooting.md).
