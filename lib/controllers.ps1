# Your controllers and what each game understands by itself (used by server.ps1).
# Everything here only reads: Windows' device list, Steam's per-game Steam Input setting and the
# results of check-controllers.ps1 (data\controller-support.json). Nothing is changed anywhere.

# PlayStation controllers by USB product id
$script:SonyPids = @{ '05C4' = 'ds4'; '09CC' = 'ds4'; '0BA0' = 'ds4'; '0CE6' = 'dualsense'; '0DF2' = 'dualsense' }
$script:PadModels = @('ds4', 'dualsense')

# PlayStation controllers Windows knows: connected now (USB or Bluetooth) or paired over Bluetooth.
# Returns model -> @{ usb = connected by cable; bt = connected over Bluetooth; paired = paired over Bluetooth }
function Get-PadDevices {
  $o = @{}
  foreach ($m in $script:PadModels) { $o[$m] = @{ usb = $false; bt = $false; paired = $false } }
  $list = @(Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE '%054C%'" -ErrorAction SilentlyContinue)
  foreach ($d in $list) {
    $id = [string]$d.DeviceID
    if ($id -match 'VID_054C&PID_([0-9A-F]{4})') { $model = $script:SonyPids[$Matches[1].ToUpper()]; if ($model -and $id -like 'HID\*') { $o[$model].usb = $true } }
    elseif ($id -match '_VID&0002054C_PID&([0-9A-F]{4})') {
      $model = $script:SonyPids[$Matches[1].ToUpper()]
      if (-not $model) { continue }
      if ($id -like 'HID\*') { $o[$model].bt = $true }                                     # the HID part exists only while connected
      elseif ($id -like 'BTHENUM\{00001124-*') { $o[$model].paired = $true }             # stays while paired, even when off
    }
  }
  return $o
}

# How each controller is connected: your choice in Settings (config.json "pads"), else what Windows
# shows now, else what Game Hub saw before (data\controllers-seen.json). link = bt | usb | none
function Get-Pads([string]$Data, $cfg) {
  $seenPath = Join-Path $Data 'data\controllers-seen.json'
  $seen = @{}
  if (Test-Path $seenPath) { try { foreach ($p in ([IO.File]::ReadAllText($seenPath) | ConvertFrom-Json).PSObject.Properties) { $seen[$p.Name] = [string]$p.Value } } catch { } }
  $dev = Get-PadDevices
  $now = (Get-Date).ToString('s'); $changed = $false
  foreach ($m in $script:PadModels) {
    foreach ($l in 'usb', 'bt') { if ($dev[$m][$l]) { $seen["$m|$l"] = $now; $changed = $true } }
  }
  if ($changed) { try { [IO.File]::WriteAllText($seenPath, (ConvertTo-Json -InputObject $seen -Compress)) } catch { } }
  $out = @()
  foreach ($m in $script:PadModels) {
    $set = if ($cfg.pads -and $cfg.pads.PSObject.Properties[$m]) { [string]$cfg.pads.$m } else { '' }
    $link = 'none'; $how = 'missing'
    if ($dev[$m].usb) { $link = 'usb'; $how = 'now' }
    elseif ($dev[$m].bt) { $link = 'bt'; $how = 'now' }
    elseif ($dev[$m].paired) { $link = 'bt'; $how = 'paired' }
    else {
      $last = @('usb', 'bt' | Where-Object { $seen["$m|$_"] } | Sort-Object { $seen["$m|$_"] } -Descending)
      if ($last.Count) { $link = $last[0]; $how = 'seen' }
    }
    $found = $link
    if ($set -in @('bt', 'usb', 'none')) { $link = $set; $how = 'set' }
    $out += [ordered]@{ model = $m; link = $link; how = $how; found = $found }
  }
  return $out
}

# Steam Input per game, from Steam's own settings (userdata\<account>\config\localconfig.vdf):
# appid -> 'on' (forced on) | 'off' (forced off). Games not listed use Steam's default.
$script:SteamInputCache = @{ file = ''; stamp = [datetime]::MinValue; map = @{} }
function Get-SteamInputModes {
  $steam = $null
  try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath } catch { }
  if (-not $steam) { return @{} }
  $steam = $steam -replace '/', '\'
  $file = $null
  try {
    $active = [int](Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam\ActiveProcess' -Name ActiveUser -ErrorAction Stop).ActiveUser
    if ($active -gt 0) { $f = Join-Path $steam "userdata\$active\config\localconfig.vdf"; if (Test-Path -LiteralPath $f) { $file = $f } }
  } catch { }
  if (-not $file) {
    $file = Get-ChildItem -Path (Join-Path $steam 'userdata\*\config\localconfig.vdf') -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $file) { return @{} }
  $stamp = (Get-Item -LiteralPath $file).LastWriteTimeUtc
  if ($script:SteamInputCache.file -eq $file -and $script:SteamInputCache.stamp -eq $stamp) { return $script:SteamInputCache.map }
  $map = @{}
  try {
    $txt = [IO.File]::ReadAllText($file)
    # tiny VDF reader: "key" "value" pairs and "key" { ... } blocks
    $stack = New-Object System.Collections.Generic.List[string]
    $key = $null
    foreach ($t in [regex]::Matches($txt, '"((?:[^"\\]|\\.)*)"|([{}])')) {
      if ($t.Groups[2].Success) {
        if ($t.Groups[2].Value -eq '{') { $stack.Add([string]$key) } elseif ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }
        $key = $null; continue
      }
      if ($null -eq $key) { $key = $t.Groups[1].Value; continue }
      if ($key -eq 'UseSteamControllerConfig' -and $stack.Count -ge 2 -and $stack[$stack.Count - 2] -eq 'apps' -and $stack[$stack.Count - 1] -match '^\d+$') {
        $v = $t.Groups[1].Value
        if ($v -eq '2') { $map[$stack[$stack.Count - 1]] = 'on' } elseif ($v -eq '0') { $map[$stack[$stack.Count - 1]] = 'off' }
      }
      $key = $null
    }
  } catch { }
  $script:SteamInputCache = @{ file = $file; stamp = $stamp; map = $map }
  return $map
}

# What is known about each game (controller-support.json) plus its Steam Input setting
function Get-ControllerFacts([string]$Data, $catalog) {
  $p = Join-Path $Data 'data\controller-support.json'
  $sup = $null
  if (Test-Path $p) { try { $sup = [IO.File]::ReadAllText($p) | ConvertFrom-Json } catch { } }
  $si = Get-SteamInputModes
  $games = [ordered]@{}
  foreach ($g in @($catalog.games | Where-Object { -not $_.duplicateOf })) {
    $f = [ordered]@{}
    if ($sup -and $sup.games -and $sup.games.PSObject.Properties[$g.id]) { foreach ($q in $sup.games.($g.id).PSObject.Properties) { $f[$q.Name] = $q.Value } }
    if ($g.id -match '^steam-(\d+)$') { $f.steamInput = $(if ($si.ContainsKey($Matches[1])) { $si[$Matches[1]] } else { 'default' }) }
    $games[$g.id] = $f
  }
  return [ordered]@{ checkedAt = $(if ($sup) { $sup.checkedAt } else { $null }); progress = $(if ($sup) { $sup.progress } else { $null }); games = $games }
}

# Your answers after playing (data\controller-feedback.json): id -> { answer, rule, at }
function Get-PadFeedback([string]$Data) {
  $p = Join-Path $Data 'data\controller-feedback.json'
  $o = [ordered]@{}
  if (Test-Path $p) { try { foreach ($q in ([IO.File]::ReadAllText($p) | ConvertFrom-Json).PSObject.Properties) { $o[$q.Name] = $q.Value } } catch { } }
  return $o
}
function Set-PadFeedback([string]$Data, [string]$id, $entry) {
  $o = Get-PadFeedback $Data
  if ($null -eq $entry) { $o.Remove($id) } else { $o[$id] = $entry }
  $p = Join-Path $Data 'data\controller-feedback.json'
  $tmp = "$p.tmp"
  [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $o -Depth 4))
  Move-Item -LiteralPath $tmp -Destination $p -Force
}
