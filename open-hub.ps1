#requires -Version 5.1
# Opens Game Hub: starts the local server if it is not answering, then opens the page
# as a Chrome app window, or an Edge app window without Chrome (falls back to the default browser).
# An app window is what watch-game.ps1 minimizes while you play.
param([string]$Root = $PSScriptRoot)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

if (-not (Test-Path (Join-Path $Data 'config.json'))) { Copy-Item (Join-Path $Root 'config.example.json') (Join-Path $Data 'config.json') }   # first run
$cfg = [IO.File]::ReadAllText((Join-Path $Data 'config.json')) | ConvertFrom-Json
$url = "http://localhost:$($cfg.port)/"

function Test-Up {
  try { return ((Invoke-WebRequest -Uri ($url + 'api/status') -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch { return $false }
}

if (-not (Test-Up)) {
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root 'server.ps1') + '"')
  for ($i = 0; $i -lt 60 -and -not (Test-Up); $i++) { Start-Sleep -Milliseconds 250 }
}

$browser = $null
foreach ($exe in 'chrome.exe', 'msedge.exe') {
  foreach ($hive in 'HKCU', 'HKLM') {
    $p = (Get-ItemProperty "${hive}:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue).'(default)'
    if ($p) { $p = $p.Trim('"') }
    if ($p -and (Test-Path -LiteralPath $p)) { $browser = $p; break }
  }
  if ($browser) { break }
}
# optional lock (lockToAccount): only this Windows account can read the key, which the page swaps for a cookie
$open = $url
if ($cfg.lockToAccount) {
  $keyFile = Join-Path $Data 'data\session.key'
  for ($i = 0; $i -lt 20 -and -not (Test-Path $keyFile); $i++) { Start-Sleep -Milliseconds 250 }
  try { $open = $url + '?k=' + ([IO.File]::ReadAllText($keyFile)).Trim() } catch { }
}
if ($browser) { Start-Process -FilePath $browser -ArgumentList "--app=$open" }
else { Start-Process $open }
