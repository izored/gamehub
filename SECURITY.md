# Security policy

## Supported versions

Only the latest release gets security fixes.

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them privately through GitHub: go to the repository's **Security** tab, choose **Report a vulnerability**, and include:

- what an attacker can do, and from where (a web page, another local user, a crafted game folder…);
- steps to reproduce, or a proof of concept;
- the Game Hub version and your Windows version.

You should get a first answer within a week. Fixes are released as soon as they're ready and credited in the changelog, unless you prefer to stay anonymous.

## Threat model

Game Hub is a **single-user, local** tool. It runs as the logged-in user and can start programs as that user, so the server is built to make sure only that user's own hub page can drive it.

**In scope.** These are protections Game Hub provides:

| Threat | Protection |
|---|---|
| A website you visit sends requests to `localhost:8790` | Every POST needs a custom `X-GameHub: 1` header. Browsers can't add it to a cross-site request without a CORS preflight, which the server never approves. Requests with a foreign `Origin` are refused too. |
| DNS rebinding (a site's hostname re-pointed at `127.0.0.1`) | Only requests whose `Host` is `localhost:<port>` or `127.0.0.1:<port>` are answered. |
| Remote machines on your network | The server binds to the loopback interface only (`127.0.0.1`). |
| Making the server run an arbitrary program or link | `/api/launch` takes a catalog id only and runs that game's stored launch record. Launcher links must match an allowlist: `steam`, `uplay`, `com.epicgames.launcher`, `origin2`, `battlenet`, `amazon-games`, or an Xbox app entry of the exact form `shell:AppsFolder\<package>!<app>` (letters, digits, `.`, `_`, `-`), which is handed to Windows Explorer. |
| Reading files outside the app | Static and artwork paths are restricted to `[A-Za-z0-9._-]` and resolved and checked to stay inside `www/`, `data/art/` or `data/covers/`. `open-folder` accepts only known game or cleanup folders. |
| Script injection through game names, paths or notes | The web app never inserts data as HTML. Responses carry `X-Content-Type-Options: nosniff`. |
| Malicious image uploads | Size limit of 25 MB. The type is decided from the file signature (JPEG, PNG or WebP only), and the file name is built by the server. |
| Excluded (for example removable) drives | Never scanned. Paths on them are rejected before they're accessed. The setup page describes drives from Windows' own drive list and only lists folder names on drives that are not excluded; the folder check rejects excluded paths before touching them. |
| Another Windows account on the same PC (when the lock is on) | See [Optional lock to your Windows account](#optional-lock-to-your-windows-account). |
| A crafted backup zip | A restore only writes Game Hub's own file names (`config.json`, `overrides.json`, `data\games.json`, `data\state.json`, `data\sessions.jsonl`, `data\game-windows.json`, `data\controller-feedback.json`, `data\covers\<name>.custom.<jpg/png/webp>`). Paths stored in the zip are never used as destinations. Backup names must match `gamehub-<date>_<time>.zip`. |
| DS4Windows' settings | Game Hub only edits `Auto Profiles.xml`, only the rules it wrote itself (listed in `data\ds4windows-managed.json`), and copies the previous file to `data\backups` first. It restarts DS4Windows only if it was running, from its own executable, and never when `ds4windowsFolder` points to a folder the running DS4Windows doesn't use. It never changes DS4Windows' other settings. |
| The launch watcher and helpers touching other programs | `watch-game.ps1` and `track-games.ps1` read only window titles and executable paths, using *query limited information* rights. They never open, read or stop a process. The only windows the watcher and `controller-helper.ps1` minimize, restore or bring to the front are browser windows titled exactly `Game Hub`. The controller helper only reads controller state through XInput. The game id the watcher receives from the server must match `[A-Za-z0-9._-]+`. |

**Out of scope.** These are known limitations:

- **Other programs running as you.** Any process on the machine can call the API, just as it could start programs itself. Game Hub adds no new capability there.
- **Other user accounts on the same PC, with the lock off** (the default). The loopback interface is shared by everyone logged in to the machine. On a PC where several people are signed in at the same time (fast user switching, Remote Desktop), another user could call your hub's API, including setting a game's executable and launching it in your session. **On a PC with other accounts, turn the [lock](#optional-lock-to-your-windows-account) on**, or use Game Hub only where every signed-in account is trusted.
- **Administrators.** An administrator account can read the lock key, like any other file on the PC.
- **Malicious game folders.** Game Hub starts the executables it finds in your game folders, and the ones you pick. It's no safer than double-clicking them.
- **Artwork sources.** Images come from Steam, Epic and Microsoft CDNs over HTTPS. They're validated as images but otherwise trusted.
- **Controller information.** PCGamingWiki is a community wiki and Steam's controller labels are set by publishers, so both can be wrong. They only change the suggestions in Settings › Controllers; DS4Windows changes only when you apply.

## Optional lock to your Windows account

Off by default. **Settings › Security** offers it when the PC has other enabled user accounts (`lockToAccount` in `config.json`).

- Turning it on creates `data\session.key` in the [data folder](docs/installation.md#where-your-data-lives) (`%LOCALAPPDATA%\GameHub`, already private to your account): 32 random bytes, written as hex. Its access list is replaced (inheritance removed) by full control for the current user, SYSTEM and Administrators only, so other standard accounts cannot read it.
- `open-hub.ps1`, which the Desktop and Start menu shortcuts run as you, reads the key and opens `http://localhost:<port>/?k=<key>`. The server answers with a cookie `gh_key=<key>; HttpOnly; SameSite=Strict` and redirects to `/`, so the key doesn't stay in the address bar or history.
- From then on every `/api/…`, `/art/…`, `/covers/…` and `/export/…` request without the right cookie gets `401` (code `locked`). The page itself and `GET /api/status` stay open, so another account sees a *Game Hub is locked* screen and nothing else: no library, no artwork, no actions.
- If the key file cannot be created or protected, the lock is switched back off and the change fails with an error, rather than appearing on while not protecting anything.
- Turning the lock off stops checking the cookie at once; the key file stays until the next time the lock is turned on, when a new key is made only if it is missing.

## Hardening tips

- On a PC with other Windows accounts, turn on **Settings › Security › Lock Game Hub to my Windows account**.
- Keep the Startup entry off on shared PCs, and start the hub only when you need it.
- Don't put game folders where other accounts can write.
- Don't change the listener to `http://+:<port>/` or open the port in the firewall. The hub is not designed to be reachable from the network.

For general advice on keeping a gaming PC safe (downloads, repacks, what to check if a game seems to have done something), see [Staying safe](docs/staying-safe.md).
