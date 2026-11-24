# Game Hub's own backups: data\backups\gamehub-YYYY-MM-DD_HHmmss.zip
#   config.json, overrides.json, the game list (games.json, with every game's folder), favorites and
#   history (state.json), play time (sessions.jsonl), remembered game windows, your answers about
#   controllers (controller-feedback.json), your custom covers,
#   plus a readable my-games.csv. Game files themselves are never backed up.
# Kept: every backup of the last 48 hours (up to 20), the newest of each of the last 7 days that have
# one, and the newest of each of the last 4 weeks. Used by server.ps1; nothing here depends on
# config.json (it can repair it).

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$script:HubBackupFiles = @('config.json', 'overrides.json', 'data\games.json', 'data\state.json', 'data\sessions.jsonl', 'data\game-windows.json', 'data\controller-feedback.json')
$script:HubBackupName = '^gamehub-(\d{4}-\d{2}-\d{2})_(\d{6})\.zip$'

function Get-HubBackupDir([string]$Data) {
  $d = Join-Path $Data 'data\backups'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

function Get-HubBackupSources([string]$Data) {
  $list = @()
  foreach ($rel in $script:HubBackupFiles) {
    $p = Join-Path $Data $rel
    if (Test-Path -LiteralPath $p -PathType Leaf) { $list += [pscustomobject]@{ Rel = $rel; Path = $p } }
  }
  foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Data 'data\covers') -File -Filter '*.custom.*' -ErrorAction SilentlyContinue)) {
    $list += [pscustomobject]@{ Rel = "data\covers\$($f.Name)"; Path = $f.FullName }
  }
  return $list
}

function Test-JsonText([string]$path) {
  try {
    $t = [IO.File]::ReadAllText($path)
    if (-not $t.Trim() -or $t.Contains([char]0)) { return $false }
    if ($path -like '*.jsonl') { return $true }
    [void]($t | ConvertFrom-Json)
    return $true
  } catch { return $false }
}

function New-HubBackup([string]$Data, [string]$Reason = 'daily', [switch]$Force, [string]$CopyTo = '', [string]$GamesCsv = '') {
  $dir = Get-HubBackupDir $Data
  $src = @(Get-HubBackupSources $Data | Where-Object { $_.Path -like '*\covers\*' -or (Test-JsonText $_.Path) })   # never back up a damaged file
  if (-not $src.Count) { return $null }
  $fp = (@($src | ForEach-Object { $i = Get-Item -LiteralPath $_.Path; "$($_.Rel)|$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" }) -join ';')
  $fpFile = Join-Path $dir 'last-backup.txt'
  if (-not $Force -and (Test-Path $fpFile) -and ([IO.File]::ReadAllText($fpFile) -eq $fp)) { return $null }   # nothing changed since the last one
  $name = 'gamehub-' + (Get-Date).ToString('yyyy-MM-dd_HHmmss') + '.zip'
  $zipPath = Join-Path $dir $name
  $tmp = "$zipPath.tmp"
  $fs = [IO.File]::Open($tmp, [IO.FileMode]::Create)
  try {
    $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
      $done = @()
      foreach ($s in $src) {
        try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $s.Path, ($s.Rel -replace '\\', '/'), [IO.Compression.CompressionLevel]::Optimal); $done += $s.Rel } catch { }
      }
      $info = [ordered]@{ created = (Get-Date).ToString('s'); reason = $Reason; files = $done }
      $e = $zip.CreateEntry('backup-info.json')
      $w = New-Object IO.StreamWriter($e.Open()); $w.Write((ConvertTo-Json -InputObject $info -Depth 3)); $w.Dispose()
      if ($GamesCsv) {
        $e = $zip.CreateEntry('my-games.csv')
        $w = New-Object IO.StreamWriter($e.Open(), (New-Object System.Text.UTF8Encoding $true)); $w.Write($GamesCsv); $w.Dispose()
      }
    } finally { $zip.Dispose() }
  } finally { $fs.Dispose() }
  Move-Item -LiteralPath $tmp -Destination $zipPath -Force
  [IO.File]::WriteAllText($fpFile, $fp)
  Remove-OldHubBackups $Data
  if ($CopyTo) {
    try { if ((Test-Path -LiteralPath $CopyTo -PathType Container)) { Copy-Item -LiteralPath $zipPath -Destination $CopyTo -Force } } catch { }
  }
  return $name
}

function Remove-OldHubBackups([string]$Data) {
  $dir = Get-HubBackupDir $Data
  $all = @(Get-ChildItem -LiteralPath $dir -File -Filter 'gamehub-*.zip' | Where-Object { $_.Name -match $script:HubBackupName } | Sort-Object Name -Descending)
  $keep = @{}; $days = @(); $weeks = @(); $recent = 0
  $cal = [Globalization.CultureInfo]::InvariantCulture.Calendar
  foreach ($f in $all) {
    [void]($f.Name -match $script:HubBackupName)
    $day = $Matches[1]
    $when = [datetime]::ParseExact("$($Matches[1])_$($Matches[2])", 'yyyy-MM-dd_HHmmss', $null)
    $d = $when.Date
    $week = '{0}-{1}' -f $d.Year, $cal.GetWeekOfYear($d, [Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
    if (((Get-Date) - $when).TotalHours -lt 48 -and $recent -lt 20) { $recent++; $keep[$f.Name] = $true }   # everything from the last two days
    if ($days -notcontains $day -and $days.Count -lt 7) { $days += $day; $keep[$f.Name] = $true }
    if ($weeks -notcontains $week -and $weeks.Count -lt 4) { $weeks += $week; $keep[$f.Name] = $true }
  }
  foreach ($f in $all) { if (-not $keep.ContainsKey($f.Name)) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue } }
}

function Get-HubBackups([string]$Data) {
  $dir = Get-HubBackupDir $Data
  $out = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter 'gamehub-*.zip' | Where-Object { $_.Name -match $script:HubBackupName } | Sort-Object Name -Descending)) {
    $reason = ''; $created = $f.LastWriteTime.ToString('s')
    try {
      $z = [IO.Compression.ZipFile]::OpenRead($f.FullName)
      try {
        $e = $z.GetEntry('backup-info.json')
        if ($e) { $r = New-Object IO.StreamReader($e.Open()); $j = $r.ReadToEnd() | ConvertFrom-Json; $r.Dispose(); $reason = [string]$j.reason; $created = [string]$j.created }
      } finally { $z.Dispose() }
    } catch { }
    $out += [ordered]@{ name = $f.Name; created = $created; sizeBytes = $f.Length; reason = $reason }
  }
  return $out
}

# extracts one entry of a backup to a temporary file; returns its path or $null
function Export-HubBackupEntry([string]$zipPath, [string]$rel) {
  $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $e = $z.GetEntry(($rel -replace '\\', '/'))
    if (-not $e) { return $null }
    $tmp = [IO.Path]::GetTempFileName()
    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $tmp, $true)
    return $tmp
  } finally { $z.Dispose() }
}

# puts a backup back; makes a "before restore" backup of the current state first
function Restore-HubBackup([string]$Data, [string]$Name) {
  if ($Name -notmatch $script:HubBackupName) { throw 'Unknown backup' }
  $zipPath = Join-Path (Get-HubBackupDir $Data) $Name
  if (-not (Test-Path -LiteralPath $zipPath)) { throw 'Unknown backup' }
  [void](New-HubBackup $Data 'before restore' -Force)
  $restored = @()
  $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try { $entries = @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() }
  foreach ($rel in $entries) {
    $relWin = $rel -replace '/', '\'
    $allowed = ($script:HubBackupFiles -contains $relWin) -or ($relWin -match '^data\\covers\\[A-Za-z0-9._-]+\.custom\.(jpg|png|webp)$')
    if (-not $allowed) { continue }
    $tmp = Export-HubBackupEntry $zipPath $rel
    if (-not $tmp) { continue }
    if ($relWin -like '*.json' -and -not (Test-JsonText $tmp)) { Remove-Item $tmp -Force; continue }
    $dest = Join-Path $Data $relWin
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    $restored += $relWin
  }
  return $restored
}

# at startup: a damaged settings or data file (empty, zeroed by a crash, not valid JSON) is put back
# from the newest backup that has a good copy. Returns one message per repaired file.
function Repair-HubFiles([string]$Data, [string]$AppRoot) {
  $notes = @()
  $dir = Join-Path $Data 'data\backups'
  $zips = @(Get-ChildItem -LiteralPath $dir -File -Filter 'gamehub-*.zip' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:HubBackupName } | Sort-Object Name -Descending)
  foreach ($rel in 'config.json', 'overrides.json', 'data\state.json', 'data\games.json') {
    $p = Join-Path $Data $rel
    if (-not (Test-Path -LiteralPath $p) -or (Test-JsonText $p)) { continue }
    $fixed = $false
    foreach ($z in $zips) {
      $tmp = $null
      try { $tmp = Export-HubBackupEntry $z.FullName $rel } catch { }
      if ($tmp -and (Test-JsonText $tmp)) {
        Copy-Item -LiteralPath $p -Destination "$p.damaged" -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $tmp -Destination $p -Force
        $notes += "$rel was damaged and was restored from the backup of $($z.Name.Substring(8, 10))"
        $fixed = $true; break
      }
      if ($tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
    if (-not $fixed -and $rel -eq 'config.json') {
      Copy-Item -LiteralPath $p -Destination "$p.damaged" -Force -ErrorAction SilentlyContinue
      Copy-Item -LiteralPath (Join-Path $AppRoot 'config.example.json') -Destination $p -Force
      $notes += 'config.json was damaged and no backup had a good copy; it was reset from config.example.json'
    } elseif (-not $fixed -and $rel -eq 'data\games.json') {
      Move-Item -LiteralPath $p -Destination "$p.damaged" -Force
      $notes += 'The game list was damaged and no backup had a good copy; it will be rebuilt by a scan'
    } elseif (-not $fixed) {
      $notes += "$rel is damaged and no backup has a good copy"
    }
  }
  return $notes
}

# a readable list of every game (opened by Excel and LibreOffice; UTF-8 with BOM)
function ConvertTo-GamesCsv($games, $favorites, $playtime) {
  $q = { param($s) '"' + ([string]$s -replace '"', '""') + '"' }
  $lines = @('Name,Launcher,Drive,Folder,Starts with,Size (GB),Play time (hours),Last played,Favorite')
  foreach ($g in @($games | Sort-Object name)) {
    $pt = if ($playtime -and $playtime.ContainsKey($g.id)) { $playtime[$g.id] } else { $null }
    $mins = [int]$g.steamMinutes; if ($pt -and $pt.minutes -gt $mins) { $mins = $pt.minutes }
    $last = @($g.lastPlayed, $(if ($pt) { $pt.last })) | Where-Object { $_ } | Sort-Object | Select-Object -Last 1
    $starts = if ($g.launch.type -eq 'exe') { ('{0} {1}' -f $g.launch.target, $g.launch.args).Trim() } else { $g.launch.target }
    $lines += (@($g.name, $g.source, $g.drive, $g.installDir, $starts, [math]::Round([double]$g.sizeBytes / 1GB, 1), [math]::Round($mins / 60, 1), $last, $(if ($favorites -contains $g.id) { 'yes' } else { '' })) | ForEach-Object { & $q $_ }) -join ','
  }
  return ($lines -join "`r`n")
}
