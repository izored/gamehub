#requires -Version 5.1
<#
  Game Hub local server  ->  http://localhost:<config.port>/   (bound to 127.0.0.1 only)

  GET  /                      the hub (www\)    GET /art/<f>, /covers/<f> artwork    GET /lang/<f> translations
  GET  /api/games             catalog + favorites/launches + play time + artwork file list (+ needsSetup, notes)
  GET  /api/status            { scanning, generatedAt }
  GET  /api/settings          folders, drives, hidden games, startup, while-you-play, play time, controller,
                              language, lock and backup options
  POST /api/settings          { gameRoots?, excludeDriveLetters?, startup?, minimizeOnLaunch?, restoreAfterGame?,
                                trackOutsideLaunches?, controllerSummon?, language?, lockToAccount?, backupCopyTo?,
                                pads?: { ds4?, dualsense?: bt|usb|none|'' } }
  GET  /api/setup/drives      first-run setup: every drive (letter, label, size, bus), nothing is read on them
  POST /api/setup/folders     { exclude }        launcher folders and suggested game folders on allowed drives
  POST /api/setup/check       { paths, exclude } checks folders typed, picked or pasted from an AI
  POST /api/setup/finish      { exclude, gameRoots, startup, minimizeOnLaunch, restoreAfterGame, lockToAccount, language }
  GET  /api/backups           list of Game Hub backups        POST /api/backups/create   back up now
  POST /api/backups/restore   { name }
  GET  /export/my-games.csv   every game with its folder, launcher, size and play time
  GET  /api/ds4windows        DS4Windows found?, profiles, per-game choices, your controllers, what each game
                              understands by itself (facts), your answers after playing (feedback)
  POST /api/ds4windows        { games: { id: on|off|profile:<name> } }  writes DS4Windows rules, restarts it
  POST /api/ds4windows/check  { force? }             look the games up online (check-controllers.ps1, background)
  POST /api/ds4windows/feedback { id, answer: fine|double|none|skip|clear, rule?: on|off }  how the controller worked
  POST /api/launch            { id }                 start a game from games.json (by id, never a path),
                                                     then watch-game.ps1 records play time, minimizes / restores the hub
  POST /api/open-folder       { id } | { path }      a game folder or a cleanup item only
  POST /api/favorite          { id, value }
  POST /api/rescan            re-run scan-games.ps1 (+ cover fetch) in the background
  POST /api/covers/fetch      { force? }             re-run fetch-covers.ps1 in the background
  POST /api/game/save         { id, name?, exe?, args?, resetExe?, hidden?, ds4? }
  POST /api/game/add          { name, exe, args? }
  POST /api/game/unhide       { id }
  POST /api/pick              { kind: exe|folder, initial? }   native Windows file/folder dialog
  POST /api/steam/search      { q }                  Steam store search (artwork picker)
  POST /api/cover/steam       { id, appid }          download that Steam app's artwork for a game
  POST /api/cover/upload?id=&kind=cover|hero   raw image bytes (JPEG/PNG/WebP, <= 25 MB)
  POST /api/cover/reset       { id, kind }           drop a custom image
  Every POST needs "X-GameHub: 1" and a same-origin Origin, so other websites cannot trigger them.
  With lockToAccount on, every /api, /art, /covers and /export request also needs the cookie that only
  open-hub.ps1 (run by this Windows account) can obtain; see lib\lock.ps1.
  Runs in the logged-in user's session (Startup shortcut), not as a service: games need the desktop.
#>
param([string]$Root = $PSScriptRoot)

# started from PowerShell 7, Windows PowerShell inherits its module path and may load PowerShell 7's modules by mistake
if ($env:PSModulePath -match '\\PowerShell\\7|\\Documents\\PowerShell\\') { $env:PSModulePath = (($env:PSModulePath -split ';') | Where-Object { $_ -and $_ -notmatch '\\PowerShell\\7|\\Documents\\PowerShell\\' }) -join ';' }

$ErrorActionPreference = 'Stop'
# $Root is the program (scripts, www); $Data is your data folder (lib\paths.ps1)
. (Join-Path $Root 'lib\paths.ps1')
$Data      = Initialize-HubData $Root
$cfgPath   = Join-Path $Data 'config.json'
$ovPath    = Join-Path $Data 'overrides.json'
$dataDir   = Join-Path $Data 'data'
$logDir    = Join-Path $Data 'logs'

# a crash while saving can leave a file empty or zeroed: put back the newest good copy first
. (Join-Path $Root 'lib\backup.ps1')
$repairNotes = @()
try { $repairNotes = @(Repair-HubFiles $Data $Root) } catch { }

if (-not (Test-Path $cfgPath)) { Copy-Item (Join-Path $Root 'config.example.json') $cfgPath }   # first run
$cfg       = [IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
$port      = [int]$cfg.port
$www       = Join-Path $Root 'www'
$artDir    = Join-Path $dataDir 'art'
$coversDir = Join-Path $dataDir 'covers'
$gamesPath = Join-Path $dataDir 'games.json'
$statePath = Join-Path $dataDir 'state.json'
$logFile   = Join-Path $logDir 'server.log'
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Game Hub Server.lnk'
$utf8      = New-Object System.Text.UTF8Encoding $false
New-Item -ItemType Directory -Force -Path $artDir, $coversDir | Out-Null
. (Join-Path $Root 'lib\steam-art.ps1')
. (Join-Path $Root 'lib\shortcuts.ps1')
. (Join-Path $Root 'lib\playtime.ps1')
. (Join-Path $Root 'lib\lock.ps1')
. (Join-Path $Root 'lib\setup.ps1')
. (Join-Path $Root 'lib\ds4windows.ps1')
. (Join-Path $Root 'lib\controllers.ps1')

function Write-Log([string]$msg) {
  try {
    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) { Move-Item $logFile "$logFile.1" -Force }
    [IO.File]::AppendAllText($logFile, ('{0}  {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg, [Environment]::NewLine), $utf8)
  } catch { }
}

$mutex = New-Object System.Threading.Mutex($false, "Local\GameHubServer-$port")
if (-not $mutex.WaitOne(0)) { exit 0 }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Prefixes.Add("http://localhost:$port/")
try { $listener.Start() } catch { Write-Log "Cannot listen on port ${port}: $($_.Exception.Message)"; exit 1 }
Write-Log "Listening on http://localhost:$port/ (pid $PID)"
foreach ($n in $repairNotes) { Write-Log "Repair: $n" }

$mime = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
           '.json' = 'application/json; charset=utf-8'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.webp' = 'image/webp'; '.svg' = 'image/svg+xml'; '.ico' = 'image/x-icon' }
$allowedHosts   = @("127.0.0.1:$port", "localhost:$port")
$allowedOrigins = @("http://127.0.0.1:$port", "http://localhost:$port")
# launcher links a game may use; anything else is refused at launch time
$uriSchemes     = '^(steam|uplay|com\.epicgames\.launcher|origin2|battlenet|amazon-games)://|^shell:AppsFolder\\[A-Za-z0-9._-]+![A-Za-z0-9._-]+$'
$languages      = @('auto', 'en', 'fr', 'es', 'pt-BR', 'de', 'ru', 'zh-Hans', 'ja', 'ko', 'pl', 'tr')
$script:job = $null
$script:ctlJob = $null                                 # the controller check runs on its own, next to scans

# ---------------------------------------------------------------- http helpers
function Send($ctx, [int]$code, [byte[]]$body, [string]$type) {
  $r = $ctx.Response
  $r.StatusCode = $code
  $r.ContentType = $type
  $r.Headers['Cache-Control'] = 'no-cache'
  $r.Headers['X-Content-Type-Options'] = 'nosniff'
  $r.ContentLength64 = $body.Length
  $r.OutputStream.Write($body, 0, $body.Length)
  $r.OutputStream.Close()
}
function Send-Json($ctx, [int]$code, [string]$json) { Send $ctx $code ($utf8.GetBytes($json)) 'application/json; charset=utf-8' }
function Send-Obj($ctx, [int]$code, $obj) { Send-Json $ctx $code (ConvertTo-Json -InputObject $obj -Depth 6 -Compress) }
# errors carry a code (and one value) so the page can show them in the user's language
$errPatterns = @(
  @('^Unknown game', 'unknownGame'), @('^Executable not found: (.+)$', 'exeNotFound'), @('^File not found: (.+)$', 'fileNotFound'),
  @('^Folder not found: (.+)$', 'folderNotFound'), @('^([A-Za-z]:) is excluded from the hub', 'excludedDrive'), @('^A scan is already running', 'scanRunning'),
  @('^Name cannot be empty|^Give the game a name', 'nameEmpty'), @('^The path must be a full path', 'exePath'), @('^Choose an executable', 'exeChoose'),
  @("^That file is inside (.+)'s folder", 'insideGame'), @('^Launch URI scheme not allowed', 'schemeNotAllowed'), @('^Game Hub is locked', 'locked'),
  @('^Only JPEG, PNG or WebP', 'imageType'), @('^Image is larger than 25 MB', 'imageSize'), @('^DS4Windows', 'ds4'), @('^Unknown backup', 'unknownBackup'))
function Send-Error($ctx, [int]$code, [string]$msg) {
  $o = [ordered]@{ error = $msg }
  foreach ($p in $errPatterns) { $m = [regex]::Match($msg, $p[0]); if ($m.Success) { $o.code = $p[1]; if ($m.Groups.Count -gt 1) { $o.arg = $m.Groups[1].Value }; break } }
  Send-Obj $ctx $code $o
}
function Send-File($ctx, [string]$baseDir, [string]$rel) {
  $base = [IO.Path]::GetFullPath($baseDir).TrimEnd('\') + '\'
  $full = [IO.Path]::GetFullPath((Join-Path $baseDir $rel))
  if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Send-Error $ctx 404 'Not found'; return }
  $type = $mime[[IO.Path]::GetExtension($full).ToLowerInvariant()]
  if (-not $type) { $type = 'application/octet-stream' }
  Send $ctx 200 ([IO.File]::ReadAllBytes($full)) $type
}
function Read-Bytes($req, [int64]$max) {
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 65536
  while (($n = $req.InputStream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n); if ($ms.Length -gt $max) { return $null } }
  return $ms.ToArray()
}
function Read-Body($req) {
  $b = Read-Bytes $req 2MB
  if ($null -eq $b) { return $null }
  $t = $utf8.GetString($b)
  if (-not $t) { return [pscustomobject]@{} }
  try { return ($t | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------- data helpers
function Write-JsonFile([string]$path, [string]$json) { $tmp = "$path.tmp"; [IO.File]::WriteAllText($tmp, $json, $utf8); Move-Item -LiteralPath $tmp -Destination $path -Force }
function Save-Config { Write-JsonFile $cfgPath (ConvertTo-Json -InputObject $cfg -Depth 5) }
function Set-Config([string]$name, $value) { $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
function Get-Catalog { if (Test-Path $gamesPath) { return ([IO.File]::ReadAllText($gamesPath) | ConvertFrom-Json) } return $null }
function Save-Catalog($c) { Write-JsonFile $gamesPath (ConvertTo-Json -InputObject $c -Depth 8) }
function Find-Game($catalog, [string]$id) { if (-not $catalog -or -not $id) { return $null }; return ($catalog.games | Where-Object { $_.id -eq $id } | Select-Object -First 1) }

function Get-State {
  $s = @{ favorites = New-Object System.Collections.ArrayList; launches = [ordered]@{} }
  if (Test-Path $statePath) {
    try {
      $j = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
      if ($j.favorites) { foreach ($f in $j.favorites) { [void]$s.favorites.Add([string]$f) } }
      if ($j.launches) { foreach ($p in $j.launches.PSObject.Properties) { $s.launches[$p.Name] = [string]$p.Value } }
    } catch { Write-Log "state.json unreadable, starting fresh: $($_.Exception.Message)" }
  }
  return $s
}
function ConvertTo-StateJson($s, [switch]$Compress) { return (ConvertTo-Json -InputObject ([ordered]@{ favorites = @($s.favorites); launches = $s.launches }) -Depth 4 -Compress:$Compress) }
function Save-State($s) { Write-JsonFile $statePath (ConvertTo-StateJson $s) }

function Get-Overrides {
  $o = if (Test-Path $ovPath) { [IO.File]::ReadAllText($ovPath) | ConvertFrom-Json } else { [pscustomobject]@{} }
  if (-not $o.PSObject.Properties['games']) { $o | Add-Member -NotePropertyName games -NotePropertyValue ([pscustomobject]@{}) }
  if (-not $o.PSObject.Properties['add']) { $o | Add-Member -NotePropertyName add -NotePropertyValue @() }
  return $o
}
function Save-Overrides($o) { Write-JsonFile $ovPath (ConvertTo-Json -InputObject $o -Depth 8) }
# Sets/clears fields of overrides.games.<id>; $null, '' or $false removes the field.
function Set-GameOverride($ov, [string]$id, [hashtable]$fields) {
  $g = $ov.games.PSObject.Properties[$id]
  $g = if ($g) { $g.Value } else { [pscustomobject]@{} }
  foreach ($k in $fields.Keys) {
    $v = $fields[$k]
    if ($null -eq $v -or ($v -is [string] -and $v -eq '') -or ($v -is [bool] -and -not $v)) { $g.PSObject.Properties.Remove($k) }
    else { $g | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force }
  }
  $ov.games.PSObject.Properties.Remove($id)
  if (@($g.PSObject.Properties).Count) { $ov.games | Add-Member -NotePropertyName $id -NotePropertyValue $g }
}

function Test-Busy { return [bool]($script:job -and -not $script:job.HasExited) }
function Test-CheckBusy { return [bool]($script:ctlJob -and -not $script:ctlJob.HasExited) }
function Start-Job2([string]$script, [string]$extra = '') {
  if (Test-Busy) { return $false }
  $script:job = Start-Process powershell.exe -PassThru -WindowStyle Hidden `
    -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root $script) + '" ' + $extra)
  Write-Log "Started $script $extra (pid $($script:job.Id))"
  return $true
}
# long-running hidden helpers (each one allows a single copy of itself)
function Start-Helper([string]$script) {
  try {
    [void](Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root $script) + '"'))
    Write-Log "Started helper $script"
  } catch { Write-Log "Could not start ${script}: $($_.Exception.Message)" }
}

function Get-ExcludedLetters {
  $ex = @($cfg.excludeDriveLetters | ForEach-Object { ([string]$_).ToUpper() })
  foreach ($v in Get-CimInstance Win32_LogicalDisk) { if ($v.VolumeName -and ($cfg.excludeVolumeLabels -contains $v.VolumeName)) { $ex += $v.DeviceID.ToUpper() } }
  return @($ex | Where-Object { $_ } | Select-Object -Unique)
}
function Test-ExcludedPath([string]$p) { return ($p.Length -ge 2 -and ((Get-ExcludedLetters) -contains $p.Substring(0, 2).ToUpper())) }
function Test-ExePath([string]$p) {
  if (-not $p) { return 'Choose an executable' }
  if (-not [IO.Path]::IsPathRooted($p) -or $p -notmatch '(?i)\.exe$') { return 'The path must be a full path to an .exe file' }
  if (Test-ExcludedPath $p) { return "$($p.Substring(0,2)) is excluded from the hub (excludeDriveLetters / excludeVolumeLabels in config.json)" }
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return "File not found: $p" }
  return $null
}
function ConvertTo-DriveLetters($list) {
  return @(@($list) | ForEach-Object { ([string]$_).Trim().ToUpper() } | Where-Object { $_ -match '^[A-Z]:?$' } | ForEach-Object { if ($_.Length -eq 1) { "${_}:" } else { $_ } } | Select-Object -Unique)
}

function Show-Picker([string]$kind, [string]$initial) {
  Add-Type -AssemblyName System.Windows.Forms
  $owner = New-Object System.Windows.Forms.Form
  $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.Opacity = 0; $owner.Width = 1; $owner.Height = 1; $owner.StartPosition = 'CenterScreen'
  $owner.Show(); $owner.Activate()
  try {
    if ($kind -eq 'folder') {
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = 'Game Hub - choose a folder'
      $d.ShowNewFolderButton = $false
      if ($initial -and (Test-Path -LiteralPath $initial)) { $d.SelectedPath = $initial }
      if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
    } else {
      $d = New-Object System.Windows.Forms.OpenFileDialog
      $d.Title = 'Game Hub - choose the game executable'
      $d.Filter = 'Programs (*.exe)|*.exe'
      $d.CheckFileExists = $true
      if ($initial -and (Test-Path -LiteralPath $initial)) { $d.InitialDirectory = $(if (Test-Path -LiteralPath $initial -PathType Leaf) { Split-Path $initial } else { $initial }) }
      if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { return $d.FileName }
    }
    return $null
  } finally { $owner.Close(); $owner.Dispose() }
}

function New-StartupShortcut {
  [void](New-HubShortcut $Root $startupLnk 'server.ps1' "Starts the Game Hub local server (http://localhost:$port)")
}
function Remove-CustomArt([string]$id, [string]$kind) {
  Get-ChildItem -LiteralPath $coversDir -Filter "$id-$kind.custom.*" -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

# on/off options; $default applies when config.json does not mention them
function Get-Flag([string]$name, [bool]$default = $true) {
  $p = $cfg.PSObject.Properties[$name]
  if ($null -eq $p -or $null -eq $p.Value) { return $default }
  return [bool]$p.Value
}
function Get-Switch([string]$name) { return (Get-Flag $name $true) }
function Get-Language { $l = [string]$cfg.language; if ($languages -contains $l) { return $l } return 'auto' }

# after a launch: watch-game.ps1 records the play session, minimizes the hub once the game window opens
# and restores it when the game has closed (one hidden watcher per game; see the script header)
function Start-Watch([string]$id) {
  if ($id -notmatch '^[A-Za-z0-9._-]+$') { return }
  $a = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root 'watch-game.ps1') + '" -GameId ' + $id
  if (Get-Switch 'minimizeOnLaunch') { $a += ' -Minimize' }
  if (Get-Switch 'restoreAfterGame') { $a += ' -Restore' }
  try { [void](Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $a) } catch { Write-Log "Could not start watch-game.ps1: $($_.Exception.Message)" }
}

function Get-PlaytimeJson {
  $sum = Get-PlaytimeSummary $Data
  $o = [ordered]@{}
  foreach ($k in $sum.Keys) { $o[$k] = [ordered]@{ minutes = $sum[$k].minutes; sessions = $sum[$k].sessions; last = $sum[$k].last } }
  return (ConvertTo-Json -InputObject $o -Compress -Depth 3)
}
function Get-GamesCsvText {
  $c = Get-Catalog
  if (-not $c) { return '' }
  return (ConvertTo-GamesCsv @($c.games | Where-Object { -not $_.duplicateOf }) @((Get-State).favorites) (Get-PlaytimeSummary $Data))
}

# daily backup: checked at startup and every 6 hours; only written when something changed
$script:lastBackupCheck = [datetime]::MinValue
function Invoke-AutoBackup([switch]$Force, [string]$Reason = 'daily') {
  if (-not $Force -and ((Get-Date) - $script:lastBackupCheck).TotalHours -lt 6) { return $null }
  $script:lastBackupCheck = Get-Date
  try {
    $n = New-HubBackup $Data $Reason -Force:$Force -CopyTo ([string]$cfg.backupCopyTo) -GamesCsv (Get-GamesCsvText)
    if ($n) { Write-Log "Backup $n ($Reason)" }
    return $n
  } catch { Write-Log "Backup failed: $($_.Exception.Message)"; return $null }
}

# lock (optional)
$script:lockKey = $null
function Enable-Lock { $script:lockKey = Get-LockKey $Data; if (-not $script:lockKey) { $script:lockKey = New-LockKey $Data }; return $script:lockKey }
if (Get-Flag 'lockToAccount' $false) { try { [void](Enable-Lock) } catch { Write-Log "Lock key unavailable, every request will be refused: $($_.Exception.Message)" } }

# DS4Windows: per-game choice in overrides.json games.<id>.ds4 = "off" | "profile:<name>"
function Get-DS4Choices {
  $ov = Get-Overrides
  $o = [ordered]@{}
  foreach ($p in $ov.games.PSObject.Properties) { if ($p.Value.ds4) { $o[$p.Name] = [string]$p.Value.ds4 } }
  return $o
}
function Update-DS4Windows {
  $ds4 = Get-DS4Windows ([string]$cfg.ds4windowsFolder)
  if (-not $ds4 -or -not $ds4.dataDir) { throw 'DS4Windows was not found on this PC' }
  $catalog = Get-Catalog
  $winFile = Join-Path $dataDir 'game-windows.json'
  $wins = if (Test-Path $winFile) { try { [IO.File]::ReadAllText($winFile) | ConvertFrom-Json } catch { $null } } else { $null }
  $rules = @()
  $choices = Get-DS4Choices
  foreach ($id in $choices.Keys) {
    $g = Find-Game $catalog $id
    if (-not $g) { continue }
    $mode = $choices[$id]
    $title = if ($wins -and $wins.$id) { [string]$wins.$id.title } else { '' }
    if ($mode -eq 'off') { $rules += [pscustomobject]@{ dir = $g.installDir; mode = 'off'; profile = ''; title = $title } }
    elseif ($mode -like 'profile:*') { $rules += [pscustomobject]@{ dir = $g.installDir; mode = 'profile'; profile = $mode.Substring(8); title = $title } }
  }
  $n = Write-DS4WindowsRules $Data $ds4 $rules
  $restarted = Restart-DS4Windows $ds4
  Write-Log "DS4Windows rules written: $n (restarted: $restarted)"
  return [ordered]@{ written = $n; restarted = $restarted; running = $ds4.running }
}

# background helpers and the first backup
if (Get-Flag 'controllerSummon' $true) { Start-Helper 'controller-helper.ps1' }
if (Get-Flag 'trackOutsideLaunches' $false) { Start-Helper 'track-games.ps1' }
[void](Invoke-AutoBackup)

# ---------------------------------------------------------------- request loop
while ($listener.IsListening) {
  try { $ctx = $listener.GetContext() } catch { break }
  $req = $ctx.Request
  try {
    if ($allowedHosts -notcontains $req.Headers['Host']) { Send-Error $ctx 403 'Forbidden host'; continue }
    $path = $req.Url.AbsolutePath
    [void](Invoke-AutoBackup)

    # optional lock: the page loads, but data and actions need this account's cookie
    if (Get-Flag 'lockToAccount' $false) {                     # no key (could not be created) = everything refused
      if ($path -eq '/' -and $req.QueryString['k']) {
        if ([string]$req.QueryString['k'] -eq $script:lockKey) { Set-LockCookie $ctx $script:lockKey }
        $ctx.Response.StatusCode = 302; $ctx.Response.Headers['Location'] = '/'; $ctx.Response.OutputStream.Close()
        continue
      }
      if ($path -match '^/(api|art|covers|export)/' -and $path -ne '/api/status' -and -not (Test-LockCookie $req $script:lockKey)) {
        Send-Error $ctx 401 'Game Hub is locked to another Windows account. Open it from its Desktop or Start menu shortcut.'
        continue
      }
    }

    if ($req.HttpMethod -eq 'GET') {
      switch -Regex ($path) {
        '^/$'           { Send-File $ctx $www 'index.html'; break }
        '^/api/games$'  {
          $catalog = if (Test-Path $gamesPath) { [IO.File]::ReadAllText($gamesPath) } else { 'null' }
          $covers = @(Get-ChildItem -LiteralPath $coversDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(jpg|png|webp)$' } | ForEach-Object { $_.Name })
          $extra = [ordered]@{ needsSetup = (-not (Test-Path $gamesPath)); notes = @($repairNotes); language = (Get-Language) }
          Send-Json $ctx 200 ('{"catalog":' + $catalog + ',"state":' + (ConvertTo-StateJson (Get-State) -Compress) + ',"playtime":' + (Get-PlaytimeJson) +
            ',"covers":' + (ConvertTo-Json -InputObject $covers -Compress) + ',"scanning":' + (Test-Busy).ToString().ToLower() +
            ',"extra":' + (ConvertTo-Json -InputObject $extra -Compress) + '}')
          break
        }
        '^/api/status$' {
          $gen = if (Test-Path $gamesPath) { (Get-Catalog).generatedAt } else { $null }
          Send-Obj $ctx 200 ([ordered]@{ scanning = (Test-Busy); generatedAt = $gen })
          break
        }
        '^/api/settings$' {
          $ov = Get-Overrides
          $hidden = @($ov.games.PSObject.Properties | Where-Object { $_.Value.hidden } | ForEach-Object { [ordered]@{ id = $_.Name; name = $(if ($_.Value.name) { $_.Value.name } else { $_.Name }) } })
          $misses = @()
          $mp = Join-Path $coversDir '_misses.json'
          if (Test-Path $mp) { $misses = @(([IO.File]::ReadAllText($mp) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Name }) }
          $ds4 = Get-DS4Windows ([string]$cfg.ds4windowsFolder)
          Send-Obj $ctx 200 ([ordered]@{
            gameRoots = @($cfg.gameRoots); excluded = @(Get-ExcludedLetters); excludedLabels = @($cfg.excludeVolumeLabels)
            drives = @(Get-SetupDrives (Get-ExcludedLetters))
            startup = (Test-Path $startupLnk); minimizeOnLaunch = (Get-Switch 'minimizeOnLaunch'); restoreAfterGame = (Get-Switch 'restoreAfterGame')
            trackOutsideLaunches = (Get-Flag 'trackOutsideLaunches' $false); controllerSummon = (Get-Flag 'controllerSummon' $true)
            language = (Get-Language); lockToAccount = (Get-Flag 'lockToAccount' $false); otherAccounts = @(Get-OtherAccounts)
            backupCopyTo = [string]$cfg.backupCopyTo; ds4windows = [bool]$ds4
            hidden = $hidden; coverMisses = $misses; port = $port; root = $Root; data = $Data })
          break
        }
        '^/api/setup/drives$' { Send-Obj $ctx 200 @{ drives = @(Get-SetupDrives (Get-ExcludedLetters)) }; break }
        '^/api/backups$'      { Send-Obj $ctx 200 ([ordered]@{ backups = @(Get-HubBackups $Data); copyTo = [string]$cfg.backupCopyTo; data = $Data }); break }
        '^/api/ds4windows$'   {
          $ds4 = Get-DS4Windows ([string]$cfg.ds4windowsFolder)
          $catalog = Get-Catalog
          $facts = if ($catalog) { Get-ControllerFacts $Data $catalog } else { [ordered]@{ checkedAt = $null; progress = $null; games = [ordered]@{} } }
          Send-Obj $ctx 200 ([ordered]@{ found = [bool]$ds4; running = $(if ($ds4) { $ds4.running } else { $false }); exe = $(if ($ds4) { $ds4.exe } else { '' })
            controls = $(if ($ds4) { $ds4.controls } else { $true }); profiles = @(if ($ds4) { $ds4.profiles }); games = (Get-DS4Choices)
            wraps = $(if ($ds4) { $ds4.wraps } else { [ordered]@{ ds4 = $true; dualsense = $true } }); hides = $(if ($ds4) { $ds4.hides } else { $false })
            pads = @(Get-Pads $Data $cfg); facts = $facts.games; checkedAt = $facts.checkedAt; progress = $facts.progress
            checking = (Test-CheckBusy); feedback = (Get-PadFeedback $Data) })
          break
        }
        '^/export/my-games\.csv$' {
          $bytes = (New-Object System.Text.UTF8Encoding $true).GetPreamble() + $utf8.GetBytes((Get-GamesCsvText))
          $ctx.Response.Headers['Content-Disposition'] = 'attachment; filename="my-games.csv"'
          Send $ctx 200 $bytes 'text/csv; charset=utf-8'
          break
        }
        '^/art/([A-Za-z0-9._-]+)$'    { Send-File $ctx $artDir $Matches[1]; break }
        '^/covers/([A-Za-z0-9._-]+)$' { Send-File $ctx $coversDir $Matches[1]; break }
        '^/lang/([A-Za-z0-9._-]+)$'   { Send-File $ctx (Join-Path $www 'lang') $Matches[1]; break }
        '^/brand/([A-Za-z0-9._-]+)$'  { Send-File $ctx (Join-Path $www 'brand') $Matches[1]; break }
        '^/([A-Za-z0-9._-]+)$'        { Send-File $ctx $www $Matches[1]; break }
        default                       { Send-Error $ctx 404 'Not found' }
      }
      continue
    }

    if ($req.HttpMethod -ne 'POST') { Send-Error $ctx 405 'Method not allowed'; continue }
    if ($req.Headers['X-GameHub'] -ne '1') { Send-Error $ctx 403 'Missing X-GameHub header'; continue }
    $origin = $req.Headers['Origin']
    if ($origin -and ($allowedOrigins -notcontains $origin)) { Send-Error $ctx 403 'Cross-origin request refused'; continue }

    # raw-bytes upload is the only POST without a JSON body
    if ($path -eq '/api/cover/upload') {
      $id = [string]$req.QueryString['id']; $kind = [string]$req.QueryString['kind']
      if ($kind -notin @('cover', 'hero')) { Send-Error $ctx 400 'kind must be cover or hero'; continue }
      if (-not (Find-Game (Get-Catalog) $id)) { Send-Error $ctx 404 'Unknown game'; continue }
      $bytes = Read-Bytes $req 25MB
      if ($null -eq $bytes) { Send-Error $ctx 413 'Image is larger than 25 MB'; continue }
      $ext = Test-ImageBytes $bytes
      if (-not $ext) { Send-Error $ctx 415 'Only JPEG, PNG or WebP images are accepted'; continue }
      Remove-CustomArt $id $kind
      $file = "$id-$kind.custom.$ext"
      [IO.File]::WriteAllBytes((Join-Path $coversDir $file), $bytes)
      Write-Log "Custom $kind for $id ($([math]::Round($bytes.Length/1KB)) KB)"
      Send-Obj $ctx 200 @{ ok = $true; file = $file }
      continue
    }

    $body = Read-Body $req
    if ($null -eq $body) { Send-Error $ctx 400 'Invalid JSON body'; continue }

    switch ($path) {
      '/api/launch' {
        $g = Find-Game (Get-Catalog) ([string]$body.id)
        if (-not $g) { Send-Error $ctx 404 'Unknown game'; break }
        $target = [string]$g.launch.target
        if ($g.launch.type -eq 'uri') {
          if ($target -notmatch $uriSchemes) { Send-Error $ctx 400 'Launch URI scheme not allowed'; break }
          if ($target -like 'shell:*') { Start-Process explorer.exe -ArgumentList $target } else { Start-Process $target }
        } else {
          if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { Send-Error $ctx 410 "Executable not found: $target"; break }
          $sp = @{ FilePath = $target; WorkingDirectory = (Split-Path $target -Parent) }
          if ($g.launch.args) { $sp.ArgumentList = [string]$g.launch.args }
          Start-Process @sp
        }
        $s = Get-State
        $s.launches[$g.id] = (Get-Date).ToString('s')
        Save-State $s
        Write-Log "Launched $($g.id) -> $target"
        Start-Watch $g.id
        Send-Obj $ctx 200 @{ ok = $true; launchedAt = $s.launches[$g.id] }
        break
      }
      '/api/open-folder' {
        $catalog = Get-Catalog
        $dir = $null
        if ($body.id) { $g = Find-Game $catalog ([string]$body.id); if ($g) { $dir = $g.installDir } }
        elseif ($body.path) {
          $want = ([string]$body.path).TrimEnd('\')
          $known = @($catalog.games | ForEach-Object { $_.installDir }) + @($catalog.cleanup | ForEach-Object { $_.path })
          $dir = $known | Where-Object { $_ -and $_.TrimEnd('\') -ieq $want } | Select-Object -First 1
        }
        if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { Send-Error $ctx 404 'Unknown folder'; break }
        Start-Process explorer.exe -ArgumentList ('"' + $dir + '"')
        Send-Obj $ctx 200 @{ ok = $true }
        break
      }
      '/api/favorite' {
        $g = Find-Game (Get-Catalog) ([string]$body.id)
        if (-not $g) { Send-Error $ctx 404 'Unknown game'; break }
        $s = Get-State
        while ($s.favorites.Contains($g.id)) { $s.favorites.Remove($g.id) }
        if ($body.value) { [void]$s.favorites.Add($g.id) }
        Save-State $s
        Send-Json $ctx 200 (ConvertTo-StateJson $s -Compress)
        break
      }
      '/api/rescan' {
        if (-not (Start-Job2 'scan-games.ps1')) { Send-Error $ctx 409 'A scan is already running'; break }
        Send-Obj $ctx 202 @{ ok = $true; scanning = $true }
        break
      }
      '/api/covers/fetch' {
        if (-not (Start-Job2 'fetch-covers.ps1' $(if ($body.force) { '-Force' } else { '' }))) { Send-Error $ctx 409 'A scan is already running'; break }
        Send-Obj $ctx 202 @{ ok = $true; scanning = $true }
        break
      }

      '/api/game/save' {
        $catalog = Get-Catalog
        $g = Find-Game $catalog ([string]$body.id)
        if (-not $g) { Send-Error $ctx 404 'Unknown game'; break }
        $ov = Get-Overrides
        $rescan = $false
        if ($body.hidden) {
          $manual = @($ov.add | Where-Object { $_.id -eq $g.id })
          if ($manual.Count) { $ov.add = @($ov.add | Where-Object { $_.id -ne $g.id }); Set-GameOverride $ov $g.id @{ hidden = $null } }
          else { Set-GameOverride $ov $g.id @{ hidden = $true; name = $g.name } }
          $catalog.games = @($catalog.games | Where-Object { $_.id -ne $g.id })
          Save-Overrides $ov; Save-Catalog $catalog
          Write-Log "Hid $($g.id)"
          Send-Obj $ctx 200 @{ ok = $true; hidden = $true }
          break
        }
        $f = @{}
        if ($null -ne $body.name) {
          $n = ([string]$body.name).Trim()
          if (-not $n) { Send-Error $ctx 400 'Name cannot be empty'; break }
          if ($n -ne $g.name) { $f.name = $n; $g.name = $n }
        }
        if ($body.resetExe) { $f.exe = $null; $f.args = $null; $rescan = $true }
        elseif ($body.exe -and ([string]$body.exe -ne [string]$g.exe -or -not $g.customExe)) {
          $err = Test-ExePath ([string]$body.exe)
          if ($err) { Send-Error $ctx 400 $err; break }
          $f.exe = [string]$body.exe
          $g.exe = $f.exe; $g.customExe = $true
          $g.launch = [pscustomobject]@{ type = 'exe'; target = $f.exe; args = [string]$body.args }
          $rescan = $true
        }
        if ($null -ne $body.args -and -not $body.resetExe) {
          $f.args = ([string]$body.args).Trim()
          if ($g.launch.type -eq 'exe') { $g.launch | Add-Member -NotePropertyName args -NotePropertyValue $f.args -Force }
        }
        $ds4Changed = $false
        if ($null -ne $body.ds4) {
          $want = [string]$body.ds4; if ($want -eq 'on') { $want = '' }
          $had = if ($ov.games.PSObject.Properties[$g.id]) { [string]$ov.games.($g.id).ds4 } else { '' }
          if ($want -ne $had -and ($want -eq '' -or $want -eq 'off' -or $want -like 'profile:*')) { $f.ds4 = $want; $ds4Changed = $true }
        }
        if ($f.Count) { Set-GameOverride $ov $g.id $f; Save-Overrides $ov; Save-Catalog $catalog }
        $ds4Result = $null
        if ($ds4Changed) { try { $ds4Result = Update-DS4Windows } catch { Write-Log "DS4Windows: $($_.Exception.Message)" } }
        if ($rescan) { [void](Start-Job2 'scan-games.ps1') }
        Write-Log "Saved $($g.id): $(($f.Keys) -join ', ')"
        Send-Obj $ctx 200 @{ ok = $true; rescanning = $rescan; ds4 = $ds4Result }
        break
      }
      '/api/game/add' {
        $name = ([string]$body.name).Trim()
        $exe = [string]$body.exe
        if (-not $name) { Send-Error $ctx 400 'Give the game a name'; break }
        $err = Test-ExePath $exe
        if ($err) { Send-Error $ctx 400 $err; break }
        $catalog = Get-Catalog
        $owner = $catalog.games | Where-Object { $exe.StartsWith($_.installDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if ($owner) { Send-Error $ctx 409 "That file is inside $($owner.name)'s folder. Edit that game (pen icon) to change its executable instead."; break }
        $ov = Get-Overrides
        $slug = (($name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')); if (-not $slug) { $slug = 'game' }
        $id = "manual-$slug"; $k = 2
        while ((Find-Game $catalog $id) -or @($ov.add | Where-Object { $_.id -eq $id }).Count) { $id = "manual-$slug-$k"; $k++ }
        $entry = [pscustomobject][ordered]@{ id = $id; name = $name; dir = (Split-Path $exe -Parent); exe = $exe; args = ([string]$body.args).Trim(); source = 'other' }
        $ov.add = @($ov.add) + $entry
        Save-Overrides $ov
        $catalog.games = @($catalog.games) + [pscustomobject][ordered]@{
          id = $id; name = $name; source = 'other'; drive = $exe.Substring(0, 2).ToUpper(); installDir = $entry.dir; exe = $exe
          launch = [pscustomobject]@{ type = 'exe'; target = $exe; args = $entry.args }; sizeBytes = 0; installedAt = (Get-Date).ToString('s'); lastPlayed = $null
          icon = ''; header = ''; cover = ''; hero = ''; logo = ''; warning = ''; note = ''; duplicateOf = ''; defaultUri = ''; customExe = $false; manual = $true }
        Save-Catalog $catalog
        [void](Start-Job2 'scan-games.ps1')
        Write-Log "Added $id -> $exe"
        Send-Obj $ctx 200 @{ ok = $true; id = $id }
        break
      }
      '/api/game/unhide' {
        $ov = Get-Overrides
        Set-GameOverride $ov ([string]$body.id) @{ hidden = $null }
        Save-Overrides $ov
        [void](Start-Job2 'scan-games.ps1')
        Send-Obj $ctx 200 @{ ok = $true }
        break
      }

      '/api/pick' {
        $p = Show-Picker ([string]$body.kind) ([string]$body.initial)
        Send-Obj $ctx 200 @{ path = $p }
        break
      }
      '/api/steam/search' {
        $q = ([string]$body.q).Trim()
        if ($q.Length -lt 2) { Send-Obj $ctx 200 @{ items = @() }; break }
        $items = @(Search-Steam $q | Select-Object -First 12)
        Send-Obj $ctx 200 @{ items = $items }
        break
      }
      '/api/cover/steam' {
        $g = Find-Game (Get-Catalog) ([string]$body.id)
        $appid = [int]$body.appid
        if (-not $g -or $appid -le 0) { Send-Error $ctx 404 'Unknown game or Steam app'; break }
        $saved = @(Save-SteamArt $appid $g.id $coversDir $null)
        if ($saved -notcontains 'cover') { Send-Error $ctx 502 "Steam has no cover image for app $appid"; break }
        Remove-CustomArt $g.id 'cover'; Remove-CustomArt $g.id 'hero'
        $ov = Get-Overrides; Set-GameOverride $ov $g.id @{ steamAppId = $appid; noArt = $null }; Save-Overrides $ov
        Write-Log "Steam art $appid for $($g.id): $($saved -join ', ')"
        Send-Obj $ctx 200 @{ ok = $true; saved = $saved }
        break
      }
      '/api/cover/reset' {
        $kind = [string]$body.kind
        if ($kind -notin @('cover', 'hero')) { Send-Error $ctx 400 'kind must be cover or hero'; break }
        Remove-CustomArt ([string]$body.id) $kind
        Send-Obj $ctx 200 @{ ok = $true }
        break
      }

      # ------------------------------------------------ first-run setup
      '/api/setup/folders' {
        $ex = ConvertTo-DriveLetters $body.exclude
        $lr = @(Get-LauncherRoots $ex)
        Send-Obj $ctx 200 ([ordered]@{ launchers = @($lr | Where-Object { $_.covered }); suggestions = @(Get-FolderSuggestions $ex @($cfg.gameRoots) $lr) })
        break
      }
      '/api/setup/check' {
        $ex = if ($null -ne $body.exclude) { ConvertTo-DriveLetters $body.exclude } else { Get-ExcludedLetters }
        Send-Obj $ctx 200 @{ results = @(Test-FolderList @($body.paths | ForEach-Object { [string]$_ }) $ex @(Get-LauncherRoots $ex)) }
        break
      }
      '/api/setup/finish' {
        $ex = ConvertTo-DriveLetters $body.exclude
        $checked = @(Test-FolderList @($body.gameRoots | ForEach-Object { [string]$_ }) $ex @())
        Set-Config 'excludeDriveLetters' @($ex)
        Set-Config 'gameRoots' @($checked | Where-Object { $_.status -eq 'ok' } | ForEach-Object { $_.path })
        foreach ($k in 'minimizeOnLaunch', 'restoreAfterGame') { if ($null -ne $body.$k) { Set-Config $k ([bool]$body.$k) } }
        if ($body.language -and $languages -contains [string]$body.language) { Set-Config 'language' ([string]$body.language) }
        if ($null -ne $body.lockToAccount) { Set-Config 'lockToAccount' ([bool]$body.lockToAccount) }
        Save-Config
        if ($null -ne $body.startup) { if ($body.startup) { New-StartupShortcut } elseif (Test-Path $startupLnk) { Remove-Item -LiteralPath $startupLnk -Force } }
        if (Get-Flag 'lockToAccount' $false) {
          try { Set-LockCookie $ctx (Enable-Lock) }
          catch { Set-Config 'lockToAccount' $false; Save-Config; $script:lockKey = $null; Write-Log "Lock failed: $($_.Exception.Message)" }
        }
        [void](Start-Job2 'scan-games.ps1')
        Write-Log "Setup finished: never read $($ex -join ', '); folders $(@($cfg.gameRoots) -join '; ')"
        Send-Obj $ctx 202 @{ ok = $true; scanning = $true; gameRoots = @($cfg.gameRoots) }
        break
      }

      # ------------------------------------------------ backups
      '/api/backups/create' {
        $n = Invoke-AutoBackup -Force -Reason 'manual'
        if (-not $n) { Send-Error $ctx 500 'Backup failed, see logs\server.log'; break }
        Send-Obj $ctx 200 @{ ok = $true; name = $n }
        break
      }
      '/api/backups/restore' {
        $restored = @(Restore-HubBackup $Data ([string]$body.name))
        $cfg = [IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
        if (Get-Flag 'lockToAccount' $false) { Set-LockCookie $ctx (Enable-Lock) } else { $script:lockKey = $null }
        Write-Log "Restored backup $($body.name): $($restored -join ', ')"
        Send-Obj $ctx 200 @{ ok = $true; restored = $restored }
        break
      }

      # ------------------------------------------------ DS4Windows
      '/api/ds4windows' {
        $ov = Get-Overrides
        $catalog = Get-Catalog
        if ($body.games) {
          foreach ($p in $body.games.PSObject.Properties) {
            if (-not (Find-Game $catalog $p.Name)) { continue }
            $v = [string]$p.Value; if ($v -eq 'on') { $v = '' }
            if ($v -eq '' -or $v -eq 'off' -or $v -like 'profile:*') { Set-GameOverride $ov $p.Name @{ ds4 = $v } }
          }
          Save-Overrides $ov
        }
        $r = Update-DS4Windows
        Send-Obj $ctx 200 ([ordered]@{ ok = $true; written = $r.written; restarted = $r.restarted; running = $r.running })
        break
      }
      '/api/ds4windows/check' {
        if (-not (Test-CheckBusy)) {
          $a = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root 'check-controllers.ps1') + '"'
          if ($body.force) { $a += ' -Force' }
          $script:ctlJob = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList $a
          Write-Log "Started check-controllers.ps1 (pid $($script:ctlJob.Id))"
        }
        Send-Obj $ctx 202 @{ ok = $true; checking = $true }
        break
      }
      '/api/ds4windows/feedback' {
        $g = Find-Game (Get-Catalog) ([string]$body.id)
        if (-not $g) { Send-Error $ctx 404 'Unknown game'; break }
        $answer = [string]$body.answer
        if ($answer -notin @('fine', 'double', 'none', 'skip', 'clear')) { Send-Error $ctx 400 'answer must be fine, double, none, skip or clear'; break }
        if ($answer -eq 'clear') { Set-PadFeedback $Data $g.id $null }
        else {
          # "Tell Game Hub" says whether DS4Windows was on or off; after playing it is the rule in place
          # (DS4Windows not running counts as "off")
          $rule = [string]$body.rule
          if ($rule -notin @('on', 'off')) {
            $ds4 = Get-DS4Windows ([string]$cfg.ds4windowsFolder)
            $choice = (Get-DS4Choices)[$g.id]
            $rule = if ($ds4 -and $ds4.running) { $(if ($choice) { $choice } else { 'on' }) } else { 'off' }
          }
          Set-PadFeedback $Data $g.id ([ordered]@{ answer = $answer; rule = $rule; at = (Get-Date).ToString('s') })
        }
        Write-Log "Controller answer for $($g.id): $answer"
        Send-Obj $ctx 200 ([ordered]@{ ok = $true; feedback = (Get-PadFeedback $Data) })
        break
      }

      '/api/settings' {
        $changed = $false; $save = $false
        if ($null -ne $body.gameRoots) {
          $roots = @()
          $known = @($cfg.gameRoots | ForEach-Object { ([string]$_).TrimEnd('\') })   # already saved: kept even if offline
          foreach ($r in @($body.gameRoots)) {
            $r = ([string]$r).Trim().TrimEnd('\'); if ($r -match '^[A-Za-z]:$') { $r += '\' }
            if (-not $r) { continue }
            if ($known -contains $r.TrimEnd('\')) { if ($roots -notcontains $r) { $roots += $r }; continue }
            if (Test-ExcludedPath $r) { Send-Error $ctx 400 "$($r.Substring(0,2)) is excluded from the hub (excludeDriveLetters / excludeVolumeLabels in config.json)"; $roots = $null; break }
            if (-not (Test-Path -LiteralPath $r -PathType Container)) { Send-Error $ctx 400 "Folder not found: $r"; $roots = $null; break }
            if ($roots -notcontains $r) { $roots += $r }
          }
          if ($null -eq $roots) { break }
          $cfg.gameRoots = $roots
          $changed = $true; $save = $true
        }
        if ($null -ne $body.excludeDriveLetters) {
          Set-Config 'excludeDriveLetters' @(ConvertTo-DriveLetters $body.excludeDriveLetters)
          $changed = $true; $save = $true
        }
        foreach ($k in 'minimizeOnLaunch', 'restoreAfterGame', 'trackOutsideLaunches', 'controllerSummon') {
          if ($null -ne $body.$k) { Set-Config $k ([bool]$body.$k); $save = $true }
        }
        if ($null -ne $body.language -and $languages -contains [string]$body.language) { Set-Config 'language' ([string]$body.language); $save = $true }
        if ($null -ne $body.backupCopyTo) {
          $b = ([string]$body.backupCopyTo).Trim()
          if ($b -and (Test-ExcludedPath $b)) { Send-Error $ctx 400 "$($b.Substring(0,2)) is excluded from the hub (excludeDriveLetters / excludeVolumeLabels in config.json)"; break }
          if ($b -and -not (Test-Path -LiteralPath $b -PathType Container)) { Send-Error $ctx 400 "Folder not found: $b"; break }
          Set-Config 'backupCopyTo' $b; $save = $true
        }
        if ($null -ne $body.pads) {
          $pd = [ordered]@{}
          if ($cfg.pads) { foreach ($q in $cfg.pads.PSObject.Properties) { $pd[$q.Name] = [string]$q.Value } }
          foreach ($m in 'ds4', 'dualsense') {
            if ($null -eq $body.pads.$m) { continue }
            $v = [string]$body.pads.$m
            if ($v -in @('bt', 'usb', 'none')) { $pd[$m] = $v } elseif ($v -eq '') { $pd.Remove($m) }
          }
          Set-Config 'pads' ([pscustomobject]$pd); $save = $true
        }
        if ($null -ne $body.lockToAccount) {
          Set-Config 'lockToAccount' ([bool]$body.lockToAccount); $save = $true
          if ($body.lockToAccount) {
            try { Set-LockCookie $ctx (Enable-Lock) }
            catch { Set-Config 'lockToAccount' $false; Save-Config; $script:lockKey = $null; Write-Log "Lock failed: $($_.Exception.Message)"; Send-Error $ctx 500 "Could not lock Game Hub: $($_.Exception.Message)"; break }
          } else { $script:lockKey = $null }
        }
        if ($save) { Save-Config }
        if ($body.trackOutsideLaunches) { Start-Helper 'track-games.ps1' }
        if ($body.controllerSummon) { Start-Helper 'controller-helper.ps1' }
        if ($null -ne $body.startup) {
          if ($body.startup) { New-StartupShortcut } elseif (Test-Path $startupLnk) { Remove-Item -LiteralPath $startupLnk -Force }
        }
        if ($changed) { [void](Start-Job2 'scan-games.ps1') }
        Send-Obj $ctx 200 ([ordered]@{ ok = $true; rescanning = $changed; startup = (Test-Path $startupLnk)
          minimizeOnLaunch = (Get-Switch 'minimizeOnLaunch'); restoreAfterGame = (Get-Switch 'restoreAfterGame')
          trackOutsideLaunches = (Get-Flag 'trackOutsideLaunches' $false); controllerSummon = (Get-Flag 'controllerSummon' $true)
          language = (Get-Language); lockToAccount = (Get-Flag 'lockToAccount' $false); backupCopyTo = [string]$cfg.backupCopyTo })
        break
      }
      default { Send-Error $ctx 404 'Not found' }
    }
  } catch {
    Write-Log "Error on $($req.HttpMethod) $($req.Url.AbsolutePath): $($_.Exception.Message)"
    try { Send-Error $ctx 500 $_.Exception.Message } catch { }
  }
}
$listener.Close()
