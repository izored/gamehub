#requires -Version 5.1
<#
  Downloads store artwork (portrait cover, wide hero, logo) for games in data\games.json that
  have none yet:
    1. Steam            Steam games by app id; others by exact (normalized) title on the Steam store
    2. Microsoft Store  games with games.<id>.msStoreId in overrides.json, or Xbox app games (their Store id)
    3. Epic             the Epic launcher's local catalog cache, for Epic installs
  Misses are remembered in data\covers\_misses.json so they are not re-searched on every scan
  (-Force retries everything and re-downloads existing artwork). Set games.<id>.steamAppId in
  overrides.json to force a specific Steam page, or games.<id>.noArt = true to skip a game.
#>
param([string]$Root = $PSScriptRoot, [switch]$Force)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

$ErrorActionPreference = 'Continue'
. (Join-Path $Root 'lib\steam-art.ps1')
$dataDir   = Join-Path $Data 'data'
$coversDir = Join-Path $dataDir 'covers'
New-Item -ItemType Directory -Force -Path $coversDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false

$catalog = [IO.File]::ReadAllText((Join-Path $dataDir 'games.json')) | ConvertFrom-Json
$ovr = if (Test-Path (Join-Path $Data 'overrides.json')) { [IO.File]::ReadAllText((Join-Path $Data 'overrides.json')) | ConvertFrom-Json } else { $null }
$missPath = Join-Path $coversDir '_misses.json'
$misses = @{}
if ((Test-Path $missPath) -and -not $Force) { ([IO.File]::ReadAllText($missPath) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $misses[$_.Name] = $_.Value } }
$have = @{}
Get-ChildItem -LiteralPath $coversDir -File | ForEach-Object { if ($_.Name -match '^(.+)-cover(\.custom)?\.(jpg|png|webp)$') { $have[$Matches[1]] = $true } }

$todo = @()       # Steam candidates
$leftover = @()   # no Steam art -> try Microsoft Store / Epic
foreach ($g in $catalog.games) {
  $o = if ($ovr -and $ovr.games) { $ovr.games.($g.id) } else { $null }
  if ($o -and $o.noArt) { continue }
  if (-not $Force -and ($have[$g.id] -or $g.cover)) { continue }
  $appid = $null
  if ($o -and $o.steamAppId) { $appid = [int]$o.steamAppId }
  elseif ($g.id -match '^steam-(\d+)$') { $appid = [int]$Matches[1] }
  elseif (-not (($o -and $o.msStoreId) -or $g.storeId) -and ($Force -or -not $misses.ContainsKey($g.id))) {
    try { $appid = Find-SteamApp $g.name } catch { Write-Host "  search failed for $($g.name): $($_.Exception.Message)" }
    if (-not $appid) { Write-Host "  - no Steam match: $($g.name)" }
  }
  if ($appid) { $todo += [pscustomobject]@{ game = $g; appid = $appid } } else { $leftover += $g }
}

$done = 0
if ($todo.Count) {
  $assets = @{}
  try { $assets = Get-SteamAssets @($todo | ForEach-Object { $_.appid } | Select-Object -Unique) } catch { Write-Host "  asset lookup failed: $($_.Exception.Message)" }
  foreach ($t in $todo) {
    $saved = Save-SteamArt $t.appid $t.game.id $coversDir $assets[$t.appid]
    if ($saved -contains 'cover') { $done++; $misses.Remove($t.game.id); Write-Host ("  + {0,-40} Steam app {1}: {2}" -f $t.game.name, $t.appid, ($saved -join ', ')) }
    else { $leftover += $t.game; Write-Host "  - Steam app $($t.appid) has no cover for $($t.game.name)" }
  }
}

# Microsoft Store (explicit msStoreId) and Epic's local catalog cache for everything Steam could not cover
if ($leftover.Count) {
  . (Join-Path $Root 'lib\store-art.ps1')
  $epic = Get-EpicCatalogCache
  foreach ($g in $leftover) {
    $o = if ($ovr -and $ovr.games) { $ovr.games.($g.id) } else { $null }
    $saved = @(); $via = ''
    $storeId = if ($o -and $o.msStoreId) { [string]$o.msStoreId } else { [string]$g.storeId }   # Xbox app games carry their Store id
    if ($storeId) {
      try { $r = Save-MsStoreArt $storeId $g.id $coversDir; $saved = @($r.saved); $via = "Microsoft Store '$($r.title)'" }
      catch { Write-Host "  Microsoft Store lookup failed for $($g.name): $($_.Exception.Message)" }
    }
    if ($saved -notcontains 'cover') {
      foreach ($e in (Get-EpicIds $g)) {
        $item = $epic["$($e.ns)/$($e.id)"]
        if (-not $item) { continue }
        $saved = @(Save-EpicArt $item $g.id $coversDir); $via = "Epic catalog '$($item.title)'"
        if ($saved -contains 'cover') { break }
      }
    }
    if ($saved -contains 'cover') { $done++; $misses.Remove($g.id); Write-Host ("  + {0,-40} {1}: {2}" -f $g.name, $via, ($saved -join ', ')) }
    else { $misses[$g.id] = "no Steam, Epic or Microsoft Store art ($((Get-Date).ToString('yyyy-MM-dd')))" }
  }
}
$mj = ConvertTo-Json -InputObject $misses -Depth 3
[IO.File]::WriteAllText($missPath, $(if ($misses.Count) { $mj } else { '{}' }), $utf8)
Write-Host ("Covers: {0} fetched, {1} games without any store art" -f $done, $misses.Count)
