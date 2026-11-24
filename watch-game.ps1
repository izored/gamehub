#requires -Version 5.1
<#
  Started by server.ps1 right after a game is launched (one hidden watcher per game):
    1. waits for the game to run: a process whose executable is inside the game's install folder
       (launchers such as Steam or Epic start it a few seconds later, so this waits up to
       -StartTimeout seconds);
    2. waits for the game's main window. Many games first show a small boot or splash screen
       (anti-cheat, launcher, logo), so a window counts at once only if it is at least 960x540;
       a smaller one counts after it has been the game's only window for 30 seconds, and a game
       with no window at all after 90 seconds gets the hub minimized anyway;
       then minimizes the Game Hub app window (-Minimize), so Windows hands the keyboard, mouse
       and controller to the game, and asks Windows to put the game in front;
    3. waits until every process of the game has exited, then restores Game Hub and brings it to
       the front (-Restore);
    4. records the play session (start to end) in data\sessions.jsonl, and remembers the game's
       main window (program and title) in data\game-windows.json for DS4Windows rules.
  "The Game Hub window" is the Chrome or Edge app window titled exactly "Game Hub", which the
  Game Hub shortcut opens. A Game Hub tab inside a normal browser window is left alone. The watcher
  only minimizes and restores that window: it never starts, stops or reads another process, and
  learns nothing about a process except the path of its executable.

  -List prints the Game Hub windows it can see and the current foreground window, then exits:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\watch-game.ps1 -List
#>
param(
  [string]$GameId = '',
  [switch]$Minimize,
  [switch]$Restore,
  [switch]$List,
  [int]$StartTimeout = 300,
  [string]$Root = $PSScriptRoot
)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

$ErrorActionPreference = 'Stop'
$logFile = Join-Path $Data 'logs\watch.log'
function Write-Log([string]$msg) {
  try {
    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 512KB) { Move-Item $logFile "$logFile.1" -Force }
    [IO.File]::AppendAllText($logFile, ('{0}  {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg, [Environment]::NewLine))
  } catch { }
}

. (Join-Path $Root 'lib\windows.ps1')
. (Join-Path $Root 'lib\playtime.ps1')

$SW_MINIMIZE = 6; $SW_RESTORE = 9
$BigW = 960; $BigH = 540          # a window this large is the game itself, not a boot screen
function Get-GameWindows($procIds) {
  return @([GameHubWindows]::TopWindows() | Where-Object { $procIds.Contains($_.Pid) -and -not $_.Minimized })
}
function Format-Title([string]$t) { return ($t -replace '[\p{Cc}\p{Cf}]', '').Trim() }   # some games hide zero-width characters in their title

if ($List) {
  $hubs = Get-HubWindows
  if ($hubs.Count) {
    foreach ($w in $hubs) { 'Game Hub window found: {0}{1}' -f (Get-ExeName $w.Pid), $(if ($w.Minimized) { ' (minimized)' } else { '' }) }
  } else {
    'No Game Hub app window found. Open Game Hub from its Desktop or Start menu shortcut: it opens as a Chrome or Edge app window.'
  }
  $fg = [GameHubWindows]::GetForegroundWindow()
  $f = [GameHubWindows]::TopWindows() | Where-Object { $_.Handle -eq $fg } | Select-Object -First 1
  'Window in front: ' + $(if ($f) { '"{0}" ({1})' -f (Format-Title $f.Title), (Get-ExeName $f.Pid) } else { 'none' })
  exit 0
}

if ($GameId -notmatch '^[A-Za-z0-9._-]+$') { exit 1 }
$mutex = New-Object System.Threading.Mutex($false, "Local\GameHubWatch-$GameId")
if (-not $mutex.WaitOne(0)) { exit 0 }   # this game is already being watched
$session = Request-SessionMutex $GameId   # $null when the outside-launch tracker already records this game

$catalog = [IO.File]::ReadAllText((Join-Path $Data 'data\games.json')) | ConvertFrom-Json
$game = $catalog.games | Where-Object { $_.id -eq $GameId } | Select-Object -First 1
if (-not $game -or -not $game.installDir -or -not (Test-Path -LiteralPath $game.installDir -PathType Container)) {
  Write-Log "${GameId}: no install folder to watch"
  exit 0
}
$dir = [string]$game.installDir

# 1. wait for the game to start, then for its main window (see the header for the boot-screen rule)
$begin = Get-Date; $seen = $null; $win = $null; $small = @{}
while (((Get-Date) - $begin).TotalSeconds -lt $StartTimeout) {
  $pids = Get-GamePids $dir
  if ($pids.Count) {
    $now = Get-Date
    if (-not $seen) { $seen = $now; Write-Log "${GameId}: running ($((@($pids) | ForEach-Object { Get-ExeName $_ }) -join ', '))" }
    $wins = Get-GameWindows $pids
    $win = $wins | Where-Object { $_.Width -ge $BigW -and $_.Height -ge $BigH } | Select-Object -First 1
    if (-not $win) {
      foreach ($w in $wins) {
        $k = [string]$w.Handle
        if (-not $small.ContainsKey($k)) {
          $small[$k] = $now
          Write-Log "${GameId}: boot screen `"$(Format-Title $w.Title)`" ($($w.Width)x$($w.Height)), waiting for the game window"
        } elseif (($now - $small[$k]).TotalSeconds -ge 30) { $win = $w; break }   # a small game, not a boot screen
      }
    }
    if ($win -or ($now - $seen).TotalSeconds -ge 90) { break }
  }
  Start-Sleep -Milliseconds 750
}
if (-not $seen) { Write-Log "${GameId}: did not start within $StartTimeout seconds, stopped watching"; exit 0 }
if ($win) { Save-GameWindow $Data $GameId ([GameHubWindows]::ProcessPath($win.Pid)) $win.Title }

# 2. step aside: minimizing the active hub window makes Windows activate the next window, the game
if ($Minimize) {
  $n = 0
  foreach ($w in Get-HubWindows) { if (-not $w.Minimized) { [void][GameHubWindows]::ShowWindowAsync($w.Handle, $SW_MINIMIZE); $n++ } }
  if ($win) { Start-Sleep -Milliseconds 400; [void][GameHubWindows]::SetForegroundWindow($win.Handle) }
  Start-Sleep -Milliseconds 300
  $front = [bool]($win -and ([GameHubWindows]::GetForegroundWindow() -eq $win.Handle))
  $what = if ($win) { "window `"$(Format-Title $win.Title)`" ($($win.Width)x$($win.Height))" } else { 'no game window after 90 seconds' }
  Write-Log "${GameId}: $what; Game Hub windows minimized: $n; game in front: $front"
}

# 3. wait until every process of the game has exited (three checks in a row, so a game that
#    restarts itself or hands over from its own launcher is not mistaken for a quit). A game
#    window that only opens after the 90-second fallback is still brought to the front once.
$late = if ($Minimize -and -not $win) { Get-Date } else { $null }
$lastAlive = Get-Date
$gone = 0
while ($gone -lt 3) {
  Start-Sleep -Seconds 2
  $pids = Get-GamePids $dir
  if (-not $pids.Count) { $gone++; continue }
  $gone = 0
  $lastAlive = Get-Date
  if ($late) {
    $big = Get-GameWindows $pids | Where-Object { $_.Width -ge $BigW -and $_.Height -ge $BigH } | Select-Object -First 1
    if ($big) {
      [void][GameHubWindows]::SetForegroundWindow($big.Handle)
      Start-Sleep -Milliseconds 300
      Write-Log "${GameId}: game window `"$(Format-Title $big.Title)`" opened late; game in front: $([GameHubWindows]::GetForegroundWindow() -eq $big.Handle)"
      Save-GameWindow $Data $GameId ([GameHubWindows]::ProcessPath($big.Pid)) $big.Title
      $late = $null
    } elseif (((Get-Date) - $late).TotalSeconds -gt 180) { $late = $null }
  }
}
$minutes = [int][Math]::Floor(($lastAlive - $seen).TotalMinutes)
Write-Log "${GameId}: closed after $minutes min"

# 4. play time
if ($session) {
  if (Add-PlaySession $Data $GameId $seen $lastAlive 'hub') { Write-Log "${GameId}: play session recorded ($minutes min)" }
  try { $session.ReleaseMutex() } catch { }
}

# 5. bring Game Hub back
if ($Restore) {
  $hubs = Get-HubWindows
  foreach ($w in $hubs) {
    if ($w.Minimized) { [void][GameHubWindows]::ShowWindowAsync($w.Handle, $SW_RESTORE) }
    Start-Sleep -Milliseconds 200
    [void][GameHubWindows]::SetForegroundWindow($w.Handle)
  }
  Start-Sleep -Milliseconds 300
  $fg = [GameHubWindows]::GetForegroundWindow()
  Write-Log ("${GameId}: Game Hub " + $(if (-not $hubs.Count) { 'window not open, nothing to restore' } elseif (@($hubs | Where-Object { $_.Handle -eq $fg }).Count) { 'restored and in front' } else { 'restored (Windows kept another window in front)' }))
}
