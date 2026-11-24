# DS4Windows per-game rules (used by server.ps1).
# DS4Windows "Auto Profiles" switch it per program in front: load a profile, or turn DS4Windows off
# while that game runs (so the game or Steam Input sees the real PlayStation controller). Its rules live in
# "Auto Profiles.xml" (in %APPDATA%\DS4Windows, or next to DS4Windows.exe for a portable copy):
#   <Programs>
#     <Program path="^C:\Games\Fortnite\" title="">            ^ = every program inside that folder
#       <Controller1>(none)</Controller1> ... <Controller8>(none)</Controller8>
#       <TurnOff>True</TurnOff>
#     </Program>
#   </Programs>
# DS4Windows reads this file only when it starts, so Game Hub restarts it after writing.
# Game Hub only touches the rules it wrote itself (listed in data\ds4windows-managed.json) and keeps
# a copy of the previous file in data\backups.

# $Folder (config.json "ds4windowsFolder", optional): DS4Windows' settings folder when Game Hub cannot find
# it. When it is not the folder the running DS4Windows uses, Game Hub writes there but never restarts
# DS4Windows (that is also how a test copy of Game Hub stays away from the real DS4Windows).
function Get-DS4Windows([string]$Folder) {
  $exe = $null; $running = $false
  $proc = @(Get-CimInstance Win32_Process -Filter "Name='DS4Windows.exe'" -ErrorAction SilentlyContinue) | Select-Object -First 1
  if ($proc) { $running = $true; $exe = $proc.ExecutablePath }
  if (-not $exe) {
    foreach ($c in "$env:USERPROFILE\Documents\DS4Windows\DS4Windows.exe", "$env:USERPROFILE\Downloads\DS4Windows\DS4Windows.exe", "$env:ProgramFiles\DS4Windows\DS4Windows.exe", "${env:ProgramFiles(x86)}\DS4Windows\DS4Windows.exe", "$env:LOCALAPPDATA\DS4Windows\DS4Windows.exe", "$env:LOCALAPPDATA\Programs\DS4Windows\DS4Windows.exe") {
      if ($c -and (Test-Path -LiteralPath $c)) { $exe = $c; break }
    }
  }
  $dsDir = $null
  if ($exe -and (Test-Path -LiteralPath (Join-Path (Split-Path $exe) 'Profiles.xml'))) { $dsDir = Split-Path $exe }
  elseif (Test-Path -LiteralPath "$env:APPDATA\DS4Windows\Profiles.xml") { $dsDir = "$env:APPDATA\DS4Windows" }
  $controls = $true                                   # the rules file is the one DS4Windows reads
  if ($Folder -and (Test-Path -LiteralPath $Folder -PathType Container)) {
    $f = $Folder.TrimEnd('\')
    if (-not $dsDir -or $f -ine $dsDir.TrimEnd('\')) { $dsDir = $f; $controls = $false }
  }
  if (-not $exe -and -not $dsDir) { return $null }
  $profiles = @()
  if ($dsDir -and (Test-Path -LiteralPath "$dsDir\Profiles")) { $profiles = @(Get-ChildItem -LiteralPath "$dsDir\Profiles" -Filter *.xml | ForEach-Object BaseName | Sort-Object) }
  # what DS4Windows takes over, and whether it hides the real controller from games
  $wrapsDs4 = $true; $wrapsDualSense = $true; $hides = $false
  if ($dsDir -and (Test-Path -LiteralPath "$dsDir\Profiles.xml")) {
    try {
      $x = New-Object System.Xml.XmlDocument; $x.Load("$dsDir\Profiles.xml")
      $v = $x.SelectSingleNode('/Profile/useExclusiveMode'); if ($v -and $v.InnerText -eq 'True') { $hides = $true }
      $v = $x.SelectSingleNode('/Profile/DeviceOptions/DS4SupportSettings/Enabled'); if ($v -and $v.InnerText -eq 'False') { $wrapsDs4 = $false }
      $v = $x.SelectSingleNode('/Profile/DeviceOptions/DualSenseSupportSettings/Enabled'); if ($v -and $v.InnerText -eq 'False') { $wrapsDualSense = $false }
    } catch { }
  }
  return [pscustomobject]@{ exe = $exe; dataDir = $dsDir; running = ($running -and $controls); controls = $controls; profiles = $profiles
    file = $(if ($dsDir) { Join-Path $dsDir 'Auto Profiles.xml' } else { $null }); hides = $hides
    wraps = [ordered]@{ ds4 = $wrapsDs4; dualsense = $wrapsDualSense } }
}

# builds one <Program> element
function New-DS4Program($doc, [string]$path, [string]$title, [string]$profile, [bool]$turnOff) {
  $el = $doc.CreateElement('Program')
  $el.SetAttribute('path', $path)
  if ($title) { $el.SetAttribute('title', $title) }
  for ($i = 1; $i -le 8; $i++) {
    $c = $doc.CreateElement("Controller$i")
    $c.InnerText = $(if ($profile -and $i -le 4) { $profile } else { '(none)' })
    [void]$el.AppendChild($c)
  }
  $t = $doc.CreateElement('TurnOff'); $t.InnerText = $(if ($turnOff) { 'True' } else { 'False' }); [void]$el.AppendChild($t)
  return $el
}

# $rules: objects with dir, mode ('off' | 'profile'), profile, title (window title, optional)
# returns the number of rules written
function Write-DS4WindowsRules([string]$Data, $ds4, $rules) {
  if (-not $ds4 -or -not $ds4.file) { throw 'DS4Windows settings folder not found' }
  $managedPath = Join-Path $Data 'data\ds4windows-managed.json'
  $managed = @()
  if (Test-Path $managedPath) { try { foreach ($m in ([IO.File]::ReadAllText($managedPath) | ConvertFrom-Json)) { $managed += [string]$m } } catch { } }   # foreach: PS 5.1 returns a JSON array as one item
  $doc = New-Object System.Xml.XmlDocument
  if (Test-Path -LiteralPath $ds4.file) {
    $bk = Join-Path $Data ('data\backups\ds4windows-auto-profiles-' + (Get-Date).ToString('yyyy-MM-dd_HHmmss') + '.xml')
    New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
    Copy-Item -LiteralPath $ds4.file -Destination $bk -Force
    $doc.Load($ds4.file)
  }
  $rootEl = $doc.SelectSingleNode('/Programs')
  if (-not $rootEl) {
    $doc.RemoveAll()
    [void]$doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null))
    $rootEl = $doc.CreateElement('Programs'); [void]$doc.AppendChild($rootEl)
  }
  foreach ($n in @($rootEl.SelectNodes('Program'))) {           # drop the rules Game Hub wrote last time
    $key = "$($n.GetAttribute('path'))|$($n.GetAttribute('title'))"
    if ($managed -contains $key) { [void]$rootEl.RemoveChild($n) }
  }
  $written = @()
  foreach ($r in @($rules)) {
    $turnOff = $r.mode -eq 'off'
    $profile = if ($r.mode -eq 'profile') { [string]$r.profile } else { '' }
    $path = '^' + ([string]$r.dir).TrimEnd('\') + '\'
    [void]$rootEl.AppendChild((New-DS4Program $doc $path '' $profile $turnOff)); $written += "$path|"
    # anti-cheat games can hide their program from DS4Windows: also match the game window's exact title
    if ($r.title -and $r.title.Trim().Length -ge 3) {
      [void]$rootEl.AppendChild((New-DS4Program $doc '' $r.title $profile $turnOff)); $written += "|$($r.title)"
    }
  }
  $comment = $doc.CreateComment(' Auto-Profile Configuration Data. ' + (Get-Date).ToString('MM/dd/yyyy HH:mm:ss') + ' (rules for games written by Game Hub) ')
  foreach ($c in @($doc.ChildNodes | Where-Object { $_.NodeType -eq 'Comment' })) { [void]$doc.RemoveChild($c) }
  [void]$doc.InsertBefore($comment, $rootEl)
  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Indent = $true; $settings.Encoding = New-Object System.Text.UTF8Encoding $false
  $w = [System.Xml.XmlWriter]::Create($ds4.file, $settings)
  try { $doc.Save($w) } finally { $w.Dispose() }
  [IO.File]::WriteAllText($managedPath, (ConvertTo-Json -InputObject @($written) -Compress))
  return $written.Count
}

# DS4Windows reads its rules only at startup: restart it if it is running
function Restart-DS4Windows($ds4) {
  if (-not $ds4.running -or -not $ds4.exe) { return $false }
  foreach ($p in @(Get-Process DS4Windows -ErrorAction SilentlyContinue)) {
    try { [void]$p.CloseMainWindow() } catch { }
    if (-not $p.WaitForExit(4000)) { try { $p.Kill(); [void]$p.WaitForExit(4000) } catch { } }
  }
  Start-Process -FilePath $ds4.exe -WorkingDirectory (Split-Path $ds4.exe)
  return $true
}
