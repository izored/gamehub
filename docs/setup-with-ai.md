# Set up Game Hub with an AI assistant

An AI assistant can take you from a fresh download to a tidy, fully linked library:

- install Game Hub;
- scan your drives;
- fix names and executables;
- spot duplicate installs;
- tell you exactly what to click in Steam, Epic, EA or Ubisoft to re-link a game.

It follows the playbook in [`AGENTS.md`](../AGENTS.md), which is written for AI assistants.

Prefer to do it yourself? See the [manual setup guide](setup-guide.md). Both paths end in the same place.

> **Only want help finding your game folders?** You don't need this page. Game Hub's setup page (and Settings › Game folders) has a **Find my game folders with an AI** button: it gives you a ready-made prompt for any assistant and checks the folders it answers with. See [Find your game folders with an AI](usage.md#find-your-game-folders-with-an-ai).

- [What the assistant will and won't do](#what-the-assistant-will-and-wont-do)
- [Option 1: an AI agent that can run commands](#option-1-an-ai-agent-that-can-run-commands)
- [Option 2: a chat assistant](#option-2-a-chat-assistant)
- [Privacy](#privacy)
- [Undoing changes](#undoing-changes)

## What the assistant will and won't do

**It will:**

- ask you **first** which drives must never be read, and save that before anything is scanned;
- install the shortcuts, and ask whether Game Hub should start with Windows;
- agree with you on your game folders, then run the scan;
- go through the results with you:
  - missing games;
  - non-games to hide;
  - names;
  - executables;
  - launcher links;
  - duplicates, with evidence for which copy you actually use;
  - covers;
- save the fixes in Game Hub's own `config.json` and `overrides.json`, after making a backup;
- test-launch a few games, **only if you agree**;
- finish with a report of what changed and what's left for you to do.

**It won't:**

- delete, move or rename game files, or touch launcher files and databases. Duplicates are only *marked*: you decide what to remove, and you remove it through the launcher.
- launch a game without asking you;
- install software or change system settings;
- sign in to anything or handle passwords. Re-linking a game inside a launcher is your click; it tells you which one.
- read drives you excluded.

## Option 1: an AI agent that can run commands

Use this with an assistant that can run PowerShell on your PC: Claude Code, OpenAI Codex CLI, GitHub Copilot (agent mode), Cursor, or similar.

1. [Download Game Hub](installation.md#install) and extract it, for example to `%LOCALAPPDATA%\Programs\GameHub`. You don't need to open the hub: the assistant prepares `config.json` with your exclusions and runs the first scan. (If you open it anyway, its setup page waits and scans nothing until you click *Scan my games*.)
2. Open that folder in your agent.
   - Claude Code reads `CLAUDE.md` automatically.
   - Most other agents read `AGENTS.md` automatically.
3. Paste this prompt:

   > Help me set up Game Hub on this PC. Follow the setup playbook in AGENTS.md step by step. Before scanning anything, ask me which drives must never be read. Don't delete anything, and ask me before launching any game.

4. Answer its questions. Keep the agent's **approve each command** setting on, so you see every command before it runs.

The same prompt works later for a tidy-up: *"Follow the setup playbook in AGENTS.md from Phase 6 to review my library."*

## Option 2: a chat assistant

Use this with a chat assistant that can't touch your PC: Claude, ChatGPT, Gemini and others. You run the commands and paste back the results.

1. Download and extract Game Hub as in Option 1 step 1.
2. Open PowerShell in the Game Hub folder:
   - **Windows 11:** right-click inside the folder in Explorer and choose **Open in Terminal**.
   - **Windows 10:** Shift + right-click inside the folder and choose **Open PowerShell window here**.
3. Open [`AGENTS.md`](../AGENTS.md), copy **all** of it, and paste it into a new chat, followed by:

   > The text above is the setup playbook for Game Hub. You can't run commands on my PC: give me one PowerShell command at a time, I'll run it in the Game Hub folder and paste the output. Start with Phase 1.

4. Run each command it gives you and paste the output back. Read each command before running it. The playbook only uses read-only commands, plus edits to Game Hub's own `config.json` and `overrides.json`.

## Privacy

Whatever the assistant reads, or you paste, is sent to the company that runs the AI. During setup that includes:

- folder paths, which may contain your Windows user name;
- drive names;
- the names of your games.

The playbook tells the assistant not to search for them online or send them anywhere else. If that's a concern, use the [manual setup guide](setup-guide.md), or remove anything private from outputs before you paste them.

Game Hub itself sends nothing anywhere except artwork lookups. See [Artwork › Network calls](artwork.md#network-calls).

## Undoing changes

Before editing, the assistant saves backups next to the originals, for example `config.json.20261121-210500.bak`.

To undo:

1. Stop the server.
2. Copy the backup back over the file.
3. Open the hub and press **Settings › Rescan now**.

Once you're happy, the `.bak` files can be deleted. They're never committed to git.

Game Hub also keeps its own daily backups of `config.json`, `overrides.json` and your library data. **Settings › Backups › Restore** puts any of them back, and backs up the current state first.
