# Play time: every finished play session is one line in data\sessions.jsonl
#   {"id":"steam-2073850","start":"2026-11-23T20:01:00","end":"2026-11-23T21:12:00","minutes":71,"by":"hub"}
# Appending one line per session is safe if the PC crashes, and two writers never clash.
# Who records a session: whoever holds the mutex Local\GameHubSession-<id> (watch-game.ps1 for games
# started from the hub, track-games.ps1 for games started elsewhere when that option is on).

function Add-PlaySession([string]$Data, [string]$GameId, [datetime]$Start, [datetime]$End, [string]$By = 'hub') {
  $minutes = [int][Math]::Floor(($End - $Start).TotalMinutes)
  if ($minutes -lt 1) { return $false }
  $line = (ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $GameId; start = $Start.ToString('s'); end = $End.ToString('s'); minutes = $minutes; by = $By }))
  $file = Join-Path $Data 'data\sessions.jsonl'
  $m = New-Object System.Threading.Mutex($false, 'Local\GameHubSessionsFile')
  $locked = $false
  try {
    try { $locked = $m.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
    [IO.File]::AppendAllText($file, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
  } finally { if ($locked) { $m.ReleaseMutex() }; $m.Dispose() }
  return $true
}

# id -> @{ minutes; sessions; last } from data\sessions.jsonl (bad lines are skipped)
function Get-PlaytimeSummary([string]$Data) {
  $sum = @{}
  $file = Join-Path $Data 'data\sessions.jsonl'
  if (-not (Test-Path $file)) { return $sum }
  foreach ($line in [IO.File]::ReadAllLines($file)) {
    if (-not $line.Trim()) { continue }
    try { $s = $line | ConvertFrom-Json } catch { continue }
    if (-not $s.id) { continue }
    if (-not $sum.ContainsKey($s.id)) { $sum[$s.id] = @{ minutes = 0; sessions = 0; last = '' } }
    $sum[$s.id].minutes += [int]$s.minutes
    $sum[$s.id].sessions += 1
    if ([string]$s.end -gt $sum[$s.id].last) { $sum[$s.id].last = [string]$s.end }
  }
  return $sum
}

# claims the right to record a game's session; returns the mutex (keep it until the session ends) or $null
function Request-SessionMutex([string]$GameId) {
  $m = New-Object System.Threading.Mutex($false, "Local\GameHubSession-$GameId")
  try { if ($m.WaitOne(0)) { return $m } } catch [System.Threading.AbandonedMutexException] { return $m }
  $m.Dispose()
  return $null
}

# remembers the main window of a game (program path and title), used for DS4Windows rules
function Save-GameWindow([string]$Data, [string]$GameId, [string]$Exe, [string]$Title) {
  $file = Join-Path $Data 'data\game-windows.json'
  $m = New-Object System.Threading.Mutex($false, 'Local\GameHubWindowsFile')
  $locked = $false
  try {
    try { $locked = $m.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
    $all = [ordered]@{}
    if (Test-Path $file) { try { $j = [IO.File]::ReadAllText($file) | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $all[$p.Name] = $p.Value } } catch { } }
    $all[$GameId] = [ordered]@{ exe = $Exe; title = $Title; seen = (Get-Date).ToString('s') }
    $tmp = "$file.tmp"
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $all -Depth 4), (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $file -Force
  } catch { } finally { if ($locked) { $m.ReleaseMutex() }; $m.Dispose() }
}
