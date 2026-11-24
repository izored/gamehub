# Non-Steam artwork sources (dot-sourced by fetch-covers.ps1 after lib\steam-art.ps1).
#  - Epic: the Epic launcher's own local catalog cache (catcache.bin) gives the official key-art URLs
#          on Epic's CDN; only the images are downloaded.
#  - Microsoft Store: the public display catalog API, for games with overrides.games.<id>.msStoreId.

function Get-EpicCatalogCache {
  $map = @{}
  $cc = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Catalog\catcache.bin'
  if (-not (Test-Path $cc)) { return $map }
  try {
    $items = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([IO.File]::ReadAllText($cc))) | ConvertFrom-Json
    foreach ($it in $items) { if ($it.namespace -and $it.id) { $map["$($it.namespace)/$($it.id)"] = $it } }
  } catch { }
  return $map
}

# Epic catalog ids for an installed game: launcher manifest first, then the .egstore records in its folder.
function Get-EpicIds($game) {
  $ids = @()
  foreach ($m in Get-ChildItem (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests\*.item') -ErrorAction SilentlyContinue) {
    try {
      $j = [IO.File]::ReadAllText($m.FullName) | ConvertFrom-Json
      if ($j.InstallLocation -and $j.InstallLocation.TrimEnd('\') -ieq $game.installDir.TrimEnd('\')) { $ids += [pscustomobject]@{ ns = $j.CatalogNamespace; id = $j.CatalogItemId } }
    } catch { }
  }
  foreach ($f in Get-ChildItem -LiteralPath (Join-Path $game.installDir '.egstore') -Filter *.mancpn -File -ErrorAction SilentlyContinue) {
    try { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; $ids += [pscustomobject]@{ ns = $j.CatalogNamespace; id = $j.CatalogItemId } } catch { }
  }
  return $ids
}

function Clear-FetchedArt([string]$id, [string]$coversDir, [string[]]$kinds) {
  foreach ($k in $kinds) { Get-ChildItem -LiteralPath $coversDir -Filter "$id-$k.*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '\.custom\.' } | Remove-Item -Force }
}

function Save-EpicArt($item, [string]$id, [string]$coversDir) {
  $pick = { param([string[]]$types) foreach ($t in $types) { $k = $item.keyImages | Where-Object type -eq $t | Select-Object -First 1; if ($k) { return $k.url } }; return $null }
  $plan = [ordered]@{ cover = (& $pick @('DieselGameBoxTall', 'OfferImageTall')); hero = (& $pick @('DieselGameBox', 'OfferImageWide')); logo = (& $pick @('DieselGameBoxLogo')) }
  $saved = @()
  foreach ($k in $plan.Keys) {
    if (-not $plan[$k]) { continue }
    Clear-FetchedArt $id $coversDir @($k)
    if (Save-RemoteImage $plan[$k] (Join-Path $coversDir "$id-$k")) { $saved += $k }
  }
  return $saved
}

function Save-MsStoreArt([string]$productId, [string]$id, [string]$coversDir) {
  $ProgressPreference = 'SilentlyContinue'
  $r = Invoke-RestMethod -Uri ('https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds=' + [uri]::EscapeDataString($productId) + '&market=US&languages=en-US') -Headers @{ 'User-Agent' = 'GameHub/1.0' } -TimeoutSec 20
  $lp = $r.Products[0].LocalizedProperties[0]
  if (-not $lp) { return [pscustomobject]@{ title = $null; saved = @() } }
  $pick = {
    param([string[]]$purposes)
    foreach ($p in $purposes) {
      $i = $lp.Images | Where-Object ImagePurpose -eq $p | Sort-Object { [int]$_.Height } -Descending | Select-Object -First 1
      if ($i) { $u = [string]$i.Uri; if ($u.StartsWith('//')) { $u = 'https:' + $u }; return $u }
    }
    return $null
  }
  $plan = [ordered]@{ cover = (& $pick @('Poster', 'BoxArt')); hero = (& $pick @('SuperHeroArt', 'TitledHeroArt')) }
  $saved = @()
  foreach ($k in $plan.Keys) {
    if (-not $plan[$k]) { continue }
    Clear-FetchedArt $id $coversDir @($k)
    if (Save-RemoteImage $plan[$k] (Join-Path $coversDir "$id-$k")) { $saved += $k }
  }
  return [pscustomobject]@{ title = $lp.ProductTitle; saved = $saved }
}
