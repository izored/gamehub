# Steam artwork helpers (dot-sourced by fetch-covers.ps1 and server.ps1).
# Talks only to Steam's public store API and image CDN; requests carry game names / app ids, nothing else.

$script:SteamUA = @{ 'User-Agent' = 'GameHub/1.0' }
$script:SteamAssetBase = 'https://shared.akamai.steamstatic.com/store_item_assets/'
$script:TrademarkChars = '[' + [char]0x2122 + [char]0x00AE + [char]0x00A9 + ']'

function Get-NormName([string]$s) {
  if (-not $s) { return '' }
  return (($s -replace $script:TrademarkChars, '').ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Search-Steam([string]$term) {
  $ProgressPreference = 'SilentlyContinue'
  $u = 'https://store.steampowered.com/api/storesearch/?term=' + [uri]::EscapeDataString($term) + '&l=english&cc=US'
  $r = Invoke-RestMethod -Uri $u -Headers $script:SteamUA -TimeoutSec 15
  return @($r.items | Where-Object { $_.type -eq 'app' } | ForEach-Object {
    [pscustomobject]@{ appid = [int]$_.id; name = [string]$_.name; thumb = [string]$_.tiny_image } })
}

# Exact (normalized) title match only - a wrong cover is worse than no cover.
function Find-SteamApp([string]$name) {
  $want = Get-NormName $name
  if (-not $want) { return $null }
  $hit = Search-Steam $name | Where-Object { (Get-NormName $_.name) -eq $want } | Select-Object -First 1
  if ($hit) { return $hit.appid }
  return $null
}

function Get-SteamAssets([int[]]$appids) {
  $ProgressPreference = 'SilentlyContinue'
  $map = @{}
  for ($i = 0; $i -lt $appids.Count; $i += 40) {
    $chunk = $appids[$i..([Math]::Min($i + 39, $appids.Count - 1))]
    $ids = ($chunk | ForEach-Object { '{"appid":' + $_ + '}' }) -join ','
    $json = '{"ids":[' + $ids + '],"context":{"language":"english","country_code":"US"},"data_request":{"include_assets":true}}'
    $r = Invoke-RestMethod -Uri ('https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json=' + [uri]::EscapeDataString($json)) -Headers $script:SteamUA -TimeoutSec 20
    foreach ($it in $r.response.store_items) { if ($it.assets) { $map[[int]$it.appid] = $it.assets } }
  }
  return $map
}

function Test-ImageBytes([byte[]]$b) {
  if (-not $b -or $b.Length -lt 12) { return $null }
  if ($b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'jpg' }
  if ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'png' }
  if ($b[0] -eq 0x52 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x46 -and $b[8] -eq 0x57 -and $b[9] -eq 0x45 -and $b[10] -eq 0x42 -and $b[11] -eq 0x50) { return 'webp' }
  return $null
}

function Save-RemoteImage([string]$url, [string]$destNoExt) {
  $ProgressPreference = 'SilentlyContinue'
  try {
    $r = Invoke-WebRequest -Uri $url -Headers $script:SteamUA -UseBasicParsing -TimeoutSec 20
    $bytes = if ($r.Content -is [byte[]]) { $r.Content } else { $r.RawContentStream.ToArray() }
    $ext = Test-ImageBytes $bytes
    if (-not $ext) { return $null }
    $dest = "$destNoExt.$ext"
    [IO.File]::WriteAllBytes($dest, $bytes)
    return $dest
  } catch { return $null }
}

# Downloads cover (600x900), hero (wide background) and, when Steam has one, the title logo.
# Files land as <id>-cover.jpg / <id>-hero.jpg / <id>-logo.png in $coversDir. Returns the kinds saved.
function Save-SteamArt([int]$appid, [string]$id, [string]$coversDir, $assets) {
  if (-not $assets) { $assets = (Get-SteamAssets @($appid))[$appid] }
  $saved = @()
  foreach ($k in 'cover', 'hero', 'logo') { Get-ChildItem -LiteralPath $coversDir -Filter "$id-$k.*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '\.custom\.' } | Remove-Item -Force }
  $fmt = if ($assets) { [string]$assets.asset_url_format } else { '' }
  $url = { param($file) if ($fmt -and $file) { $script:SteamAssetBase + $fmt.Replace('${FILENAME}', $file) } else { $null } }
  $legacy = "https://cdn.cloudflare.steamstatic.com/steam/apps/$appid"
  $coverUrls = @((& $url $assets.library_capsule_2x), (& $url $assets.library_capsule), "$legacy/library_600x900_2x.jpg") | Where-Object { $_ }
  foreach ($u in $coverUrls) { if (Save-RemoteImage $u (Join-Path $coversDir "$id-cover")) { $saved += 'cover'; break } }
  $heroUrls = @((& $url $assets.library_hero), "$legacy/library_hero.jpg") | Where-Object { $_ }
  foreach ($u in $heroUrls) { if (Save-RemoteImage $u (Join-Path $coversDir "$id-hero")) { $saved += 'hero'; break } }
  $logoUrls = @((& $url $assets.library_logo), "$legacy/logo.png") | Where-Object { $_ }
  foreach ($u in $logoUrls) { if (Save-RemoteImage $u (Join-Path $coversDir "$id-logo")) { $saved += 'logo'; break } }
  return $saved
}
