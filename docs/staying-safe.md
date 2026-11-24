# Staying safe

Game Hub can start any game on your PC, so it is worth knowing a few basics about keeping a gaming PC safe. This page is general advice for anyone who plays on Windows. It is not about any particular game or launcher.

- [Where games come from](#where-games-come-from)
- [Signs that something is wrong](#signs-that-something-is-wrong)
- [If you think a game or a download did something](#if-you-think-a-game-or-a-download-did-something)
- [Good habits](#good-habits)
- [What Game Hub does, and what it does not do](#what-game-hub-does-and-what-it-does-not-do)

## Where games come from

- **Official stores are the safest source.** Steam, Epic Games, GOG, the EA app, Ubisoft Connect, Battle.net, the Xbox app and itch.io deliver games through their own installers and update them.
- **Repacks, cracks and "free" copies of paid games** are one of the most common ways unwanted software reaches a gaming PC. The game itself can work perfectly while its installer quietly adds something else: a program that starts with Windows, a scheduled task, a browser extension, a miner.
- **Cheats, trainers, unofficial mod managers and "FPS boosters"** from unknown sites carry the same risk.
- **Links posted in chats, video comments or direct messages**, especially ones that say "disable your antivirus first, it's a false positive", are a classic trap.

## Signs that something is wrong

None of these prove there is a problem, but each one is worth a look:

- Your browser opens by itself, often at logon or every few minutes, on ads or odd websites.
- A new program, shortcut or task starts with Windows, and you did not add it.
- Your antivirus was turned off, or has exclusions (folders it no longer checks) you did not add.
- The PC is slow, hot or loud while you are doing nothing.
- New browser extensions, or a homepage or search engine you did not choose.
- Login alerts from your accounts, or friends receiving messages you did not send.

## If you think a game or a download did something

1. **Stay calm and stop running it.** Do not run the installer or the game again "to check".
2. **Scan the PC.** Open *Windows Security › Virus & threat protection › Scan options*, run a **Full scan**, then a **Microsoft Defender Offline scan** (it restarts the PC and scans before Windows starts). A second opinion from another reputable scanner does no harm.
3. **Look at what starts with Windows:**
   - *Task Manager › Startup apps*, and *Settings › Apps › Startup*.
   - *Task Scheduler*: look for tasks with random-looking names, tasks that run every few minutes, or tasks that start `powershell`, `cmd`, `wscript`, `mshta` or a program in `AppData` or `Temp`.
   - For a complete list, Microsoft's free **Autoruns** tool (Sysinternals) shows everything that starts automatically.
4. **Check your browsers:** extensions, homepage, search engine, and notifications you allowed from websites.
5. **Secure your accounts from another, clean device** (your phone is fine): change the password of your email first, then Steam, Epic, Discord, your other launchers and anything you logged into on that PC. Turn on two-factor authentication, and sign out of every other session (Steam and Discord both offer this). A changed password is what invalidates stolen logins.
6. **Money:** if you use banking, payment or cryptocurrency apps on that PC, check them from the clean device and contact your bank if anything looks off.
7. **When in doubt, start fresh.** Back up your personal files (documents, photos, game saves; not programs), then use *Settings › System › Recovery › Reset this PC › Remove everything*. Reinstall games from official stores.

## Good habits

- Keep Windows, your graphics driver and your launchers up to date.
- Read admin prompts ("Do you want to allow this app to make changes?") before saying yes: an installer with administrator rights can change anything on the PC.
- Never turn off your antivirus because a download tells you to.
- Use cloud saves where your launcher offers them, and keep a backup of your personal files (OneDrive, File History or an external drive).
- On a shared PC, give everyone their own Windows account. Game Hub can be locked to yours (Settings › Security).

## What Game Hub does, and what it does not do

- Game Hub **is not an antivirus.** It lists the games it finds on your drives; it cannot tell a safe game from an unsafe one.
- It **never downloads or installs games.** It only goes online to download cover art (see [Privacy](../README.md#privacy)).
- It **starts only games from its own list**, by their id. A web page cannot make it run a file. See [SECURITY.md](../SECURITY.md).
- It **never deletes anything** for you. The Cleanup panel only opens folders.
- Its scripts are plain text files you (or someone you trust) can read.

Found a security problem in Game Hub itself? Please report it privately, as described in [SECURITY.md](../SECURITY.md).
