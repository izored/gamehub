#requires -Version 5.1
<#
  Controller check (Settings > Controllers > "Check my games"). Started hidden by server.ps1; you can
  also run it by hand:  powershell -ExecutionPolicy Bypass -File check-controllers.ps1 [-Force]

  For every game in the library it finds out which PlayStation controllers the game understands by
  itself, so Game Hub can suggest whether DS4Windows should stay on or turn off while the game runs:
    - PCGamingWiki (www.pcgamingwiki.com): PlayStation controller support, which models, USB / Bluetooth
    - Steam's store (store.steampowered.com): the "DualShock / DualSense Controller Support" labels
    - the game folder: Sony's own controller library (libScePad.dll) means the game reads them itself
  Requests carry game names and Steam app numbers only. Results go to data\controller-support.json.
  Games checked in the last 30 days are skipped unless -Force.
#>
param([string]$Root = $PSScriptRoot, [switch]$Force)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $Root 'lib\steam-art.ps1')
$mutex = New-Object System.Threading.Mutex($false, 'Local\GameHubControllerCheck')
if (-not $mutex.WaitOne(0)) { exit 0 }

$outPath = Join-Path $Data 'data\controller-support.json'
$logFile = Join-Path $Data 'logs\scan.log'
$ua = @{ 'User-Agent' = 'GameHub/1.1 (controller check)' }
function Write-Log([string]$msg) { try { [IO.File]::AppendAllText($logFile, ('{0}  controllers: {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg, [Environment]::NewLine)) } catch { } }

$cfg = [IO.File]::ReadAllText((Join-Path $Data 'config.json')) | ConvertFrom-Json
$ov = $null; $ovPath = Join-Path $Data 'overrides.json'
if (Test-Path $ovPath) { $ov = [IO.File]::ReadAllText($ovPath) | ConvertFrom-Json }
$excluded = @($cfg.excludeDriveLetters | ForEach-Object { ([string]$_).ToUpper() })
foreach ($v in Get-CimInstance Win32_LogicalDisk) { if ($v.VolumeName -and ($cfg.excludeVolumeLabels -contains $v.VolumeName)) { $excluded += $v.DeviceID.ToUpper() } }

# ---------------------------------------------------------------- PCGamingWiki
function Invoke-Pcgw([string]$query) {
  Start-Sleep -Milliseconds 400                       # be polite to a community wiki
  return Invoke-RestMethod -Uri ('https://www.pcgamingwiki.com/w/api.php?' + $query) -Headers $ua -TimeoutSec 20
}
function Get-PcgwTitleByAppId([int]$appid) {
  Start-Sleep -Milliseconds 400
  $req = [Net.HttpWebRequest]::Create("https://www.pcgamingwiki.com/api/appid.php?appid=$appid")
  $req.AllowAutoRedirect = $false; $req.UserAgent = $ua['User-Agent']; $req.Timeout = 20000
  $res = $null
  try {
    $res = $req.GetResponse()
    $loc = [string]$res.Headers['Location']
    if ($loc -match '/wiki/(.+)$') { return ([uri]::UnescapeDataString($Matches[1]) -replace '_', ' ') }
  } catch { } finally { if ($res) { $res.Close() } }
  return $null
}
function Get-PcgwTitleByName([string]$name) {
  $want = Get-NormName $name
  $r = Invoke-Pcgw ('action=opensearch&namespace=0&limit=8&redirects=resolve&format=json&search=' + [uri]::EscapeDataString($name))
  foreach ($t in @($r[1])) { if ((Get-NormName ([string]$t)) -eq $want) { return [string]$t } }
  return $null
}
# plain text of a template value: no references, links or templates
function Get-CleanText([string]$s) {
  $s = $s -replace '(?s)<ref[^>]*/>', '' -replace '(?s)<ref[^>]*>.*?</ref>', '' -replace '<[^>]+>', ''
  $s = $s -replace '\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', '$1' -replace '\{\{[^{}]*\}\}', '' -replace "'''?", ''
  return ($s -replace '\s+', ' ').Trim()
}
function Get-PcgwInput([string]$title) {
  $r = Invoke-Pcgw ('action=parse&prop=wikitext&format=json&formatversion=2&redirects=1&page=' + [uri]::EscapeDataString($title))
  if (-not $r.parse) { return $null }
  $w = [string]$r.parse.wikitext
  $i = $w.IndexOf('{{Input')
  $f = @{}
  if ($i -ge 0) {
    $block = $w.Substring($i)
    $end = $block.IndexOf("`n}}"); if ($end -gt 0) { $block = $block.Substring(0, $end) }
    foreach ($m in [regex]::Matches($block, '(?m)^\|\s*([a-z0-9 ]+?)\s*=(.*)$')) { $f[$m.Groups[1].Value] = Get-CleanText $m.Groups[2].Value }
  }
  $o = [ordered]@{ page = [string]$r.parse.title; ps = 'unknown'; models = @(); usb = $null; bt = $null; btListed = $false; note = '' }
  $ps = ([string]$f['playstation controllers']).ToLowerInvariant()
  if ($ps -in @('true', 'limited')) { $o.ps = 'yes' } elseif ($ps -in @('false', 'hackable')) { $o.ps = 'no' }
  foreach ($t in ([string]$f['playstation controller models']).ToLowerInvariant().Split(',')) {
    $t = $t.Trim()
    if ($t -in @('ds4', 'dualshock 4', 'dualshock4', 'playstation 4', 'ps4')) { $o.models += 'ds4' }
    elseif ($t -in @('ds', 'dse', 'dualsense', 'dualsense edge', 'playstation 5', 'ps5')) { $o.models += 'dualsense' }
  }
  $o.models = @($o.models | Select-Object -Unique)
  $modes = ([string]$f['playstation connection modes']).ToLowerInvariant()
  $note = (@([string]$f['playstation connection modes notes'], [string]$f['playstation controllers notes']) | Where-Object { $_ }) -join ' '
  if ($modes -and $modes -ne 'unknown') {                      # 'unknown' = not stated
    $o.usb = ($modes -match 'wired|usb')
    if ($modes -match 'bluetooth|wireless') {
      $bt = @($(if ($o.models.Count) { $o.models } else { 'ds4', 'dualsense' }))
      if ($note -match '(?i)\bonly\b' -and $note -match '(?i)bluetooth|wireless') {   # e.g. "Bluetooth only for DualSense"
        $named = @()
        if ($note -match '(?i)dualshock|\bds4\b|\bps4\b') { $named += 'ds4' }
        if ($note -match '(?i)dualsense|\bps5\b') { $named += 'dualsense' }
        if ($named.Count) { $bt = $named }
      }
      $o.bt = $bt; $o.btListed = $true
    } else { $o.bt = @(); $o.btListed = $false }               # only 'Wired' listed: Bluetooth may just be untested
  }
  if ($note.Length -gt 220) { $note = $note.Substring(0, 217) + '...' }
  $o.note = $note
  return $o
}

# ---------------------------------------------------------------- Steam store labels
function Get-SteamPadLabels([int]$appid) {
  $r = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$appid&filters=categories" -Headers $ua -TimeoutSec 20
  $d = $r.$appid
  if (-not $d -or -not $d.success) { return $null }
  $ids = @($d.data.categories | ForEach-Object { [int]$_.id })
  return [ordered]@{ appid = $appid; ds4 = [bool]($ids -contains 55 -or $ids -contains 56); dualsense = [bool]($ids -contains 57 -or $ids -contains 58)
    full = [bool]($ids -contains 28); partial = [bool]($ids -contains 18) }
}

# ---------------------------------------------------------------- the game folder
# Sony's PC controller library (or the DualSense one many ports use): the game reads PlayStation controllers itself
function Find-PadLibrary([string]$dir) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
  if ($excluded -contains $dir.Substring(0, 2).ToUpper()) { return @() }
  $found = @()
  $todo = New-Object System.Collections.Generic.Stack[object]
  $todo.Push(@($dir, 0))
  while ($todo.Count -and $found.Count -eq 0) {
    $item = $todo.Pop(); $d = $item[0]; $depth = $item[1]
    foreach ($pat in 'libScePad*.dll', 'ds5w*.dll') {
      try { foreach ($f in [IO.Directory]::GetFiles($d, $pat)) { $found += [IO.Path]::GetFileName($f) } } catch { }
    }
    if ($depth -ge 6) { continue }
    try {
      foreach ($sub in [IO.Directory]::GetDirectories($d)) {
        try { if (([IO.File]::GetAttributes($sub) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue } } catch { continue }
        $todo.Push(@($sub, ($depth + 1)))
      }
    } catch { }
  }
  return @($found | Select-Object -Unique)
}

# ---------------------------------------------------------------- run
$catalog = [IO.File]::ReadAllText((Join-Path $Data 'data\games.json')) | ConvertFrom-Json
$games = @($catalog.games | Where-Object { -not $_.duplicateOf })
$old = $null
if (Test-Path $outPath) { try { $old = [IO.File]::ReadAllText($outPath) | ConvertFrom-Json } catch { } }
$results = [ordered]@{}
if ($old -and $old.games) { foreach ($p in $old.games.PSObject.Properties) { if ($games.id -contains $p.Name) { $results[$p.Name] = $p.Value } } }
function Save-Results($progress) {
  $o = [ordered]@{ checkedAt = (Get-Date).ToString('s'); progress = $progress; games = $results }
  $tmp = "$outPath.tmp"
  [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $o -Depth 6))
  Move-Item -LiteralPath $tmp -Destination $outPath -Force
}

Write-Log "check started ($($games.Count) games$(if ($Force) { ', all again' }))"
$n = 0; $found = 0
foreach ($g in $games) {
  $n++
  $prev = $results[$g.id]
  if (-not $Force -and $prev -and $prev.checkedAt) {
    try { if (((Get-Date) - [datetime]$prev.checkedAt).TotalDays -lt 30) { continue } } catch { }
  }
  Save-Results ([ordered]@{ done = $n - 1; total = $games.Count })
  $e = [ordered]@{ checkedAt = (Get-Date).ToString('s'); pcgw = $null; steam = $null; files = @() }
  # Steam app number: your choice (artwork picker), the Steam id, or Steam's store search (exact name only)
  $appid = $null
  if ($ov -and $ov.games -and $ov.games.PSObject.Properties[$g.id] -and $ov.games.($g.id).steamAppId) { $appid = [int]$ov.games.($g.id).steamAppId }
  elseif ($g.id -match '^steam-(\d+)$') { $appid = [int]$Matches[1] }
  else { try { $appid = Find-SteamApp $g.name } catch { } }
  try {
    $title = $null
    if ($appid) { $title = Get-PcgwTitleByAppId $appid }
    if (-not $title) { $title = Get-PcgwTitleByName $g.name }
    if ($title) { $e.pcgw = Get-PcgwInput $title }
  } catch { Write-Log "PCGamingWiki failed for $($g.name): $($_.Exception.Message)" }
  if ($appid) { try { $e.steam = Get-SteamPadLabels $appid } catch { Write-Log "Steam failed for $($g.name): $($_.Exception.Message)" } }
  try { $e.files = @(Find-PadLibrary ([string]$g.installDir)) } catch { }
  if ($e.pcgw -or $e.steam -or $e.files.Count) { $found++ }
  $results[$g.id] = $e
}
Save-Results $null
Write-Log "check finished: $found of $($games.Count) games have controller information"
