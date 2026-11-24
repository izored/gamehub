#requires -Version 5.1
<#
  Optional (Settings > While you play > "Count games started outside Game Hub", trackOutsideLaunches in
  config.json). Started hidden by server.ps1. Once a minute it looks at which programs are running and
  records a play session for every game in the library whose program runs from the game's folder,
  however it was started (Steam, a desktop shortcut...). Games started from Game Hub are recorded by
  watch-game.ps1 instead: the per-game mutex makes sure a session is never counted twice.
  It only reads the list of running programs' paths, nothing else.
#>
param([string]$Root = $PSScriptRoot, [int]$Seconds = 60)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

$ErrorActionPreference = 'Stop'
$mutex = New-Object System.Threading.Mutex($false, 'Local\GameHubTracker')
if (-not $mutex.WaitOne(0)) { exit 0 }
. (Join-Path $Root 'lib\windows.ps1')
. (Join-Path $Root 'lib\playtime.ps1')
$logFile = Join-Path $Data 'logs\watch.log'
function Write-Log([string]$msg) { try { [IO.File]::AppendAllText($logFile, ('{0}  tracker: {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg, [Environment]::NewLine)) } catch { } }

$gamesPath = Join-Path $Data 'data\games.json'
$cfgPath = Join-Path $Data 'config.json'
$stamp = $null; $dirs = @{}
$active = @{}    # id -> @{ start; last; mutex }
Write-Log "started (every $Seconds s)"
while ($true) {
  try {
    # stop when the option is switched off
    $cfg = [IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
    if (-not $cfg.trackOutsideLaunches) { break }
    # reload the game list when a scan rewrote it
    $t = (Get-Item $gamesPath).LastWriteTimeUtc
    if ($t -ne $stamp) {
      $stamp = $t; $dirs = @{}
      foreach ($g in ([IO.File]::ReadAllText($gamesPath) | ConvertFrom-Json).games) { if ($g.installDir -and -not $g.duplicateOf) { $dirs[$g.id] = ([string]$g.installDir).TrimEnd('\') + '\' } }
    }
    $paths = Get-ProcessPaths
    $now = Get-Date
    foreach ($id in @($dirs.Keys)) {
      $prefix = $dirs[$id]
      $running = $false
      foreach ($p in $paths) { if ($p.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $running = $true; break } }
      if ($running) {
        if ($active.ContainsKey($id)) { $active[$id].last = $now }
        else {
          $m = Request-SessionMutex $id          # held by watch-game.ps1 when the game was started from the hub
          if ($m) { $active[$id] = @{ start = $now; last = $now; mutex = $m }; Write-Log "$id started" }
        }
      } elseif ($active.ContainsKey($id)) {
        $a = $active[$id]
        if (Add-PlaySession $Data $id $a.start $a.last 'tracker') { Write-Log "$id session recorded" }
        try { $a.mutex.ReleaseMutex() } catch { }
        $active.Remove($id)
      }
    }
  } catch { Write-Log "error: $($_.Exception.Message)" }
  Start-Sleep -Seconds $Seconds
}
foreach ($id in @($active.Keys)) { $a = $active[$id]; [void](Add-PlaySession $Data $id $a.start $a.last 'tracker'); try { $a.mutex.ReleaseMutex() } catch { } }
Write-Log 'stopped (option switched off)'
