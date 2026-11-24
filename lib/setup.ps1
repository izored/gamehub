# The first-run setup page and Settings > Drives / Game folders (used by server.ps1).
# Excluded drives are never read: drives are described from Windows' own drive list (letter, label,
# size, bus), and folders are only listed on drives that are not excluded.

function Get-SetupDrives([string[]]$Excluded) {
  $bus = @{}
  try {
    foreach ($p in @(Get-Partition -ErrorAction Stop | Where-Object { $_.DriveLetter })) {
      $d = Get-Disk -Number $p.DiskNumber -ErrorAction SilentlyContinue
      if ($d) { $bus[("$($p.DriveLetter):").ToUpper()] = [string]$d.BusType }
    }
  } catch { }
  if (-not $bus.Count) {
    foreach ($dd in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)) {
      $usb = $dd.InterfaceType -eq 'USB' -or $dd.PNPDeviceID -like 'USBSTOR*' -or $dd.MediaType -match 'External'
      foreach ($part in @(Get-CimAssociatedInstance -InputObject $dd -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue)) {
        foreach ($ld in @(Get-CimAssociatedInstance -InputObject $part -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue)) { $bus[$ld.DeviceID.ToUpper()] = $(if ($usb) { 'USB' } else { [string]$dd.InterfaceType }) }
      }
    }
  }
  $out = @()
  foreach ($v in @(Get-CimInstance Win32_LogicalDisk | Sort-Object DeviceID)) {
    $letter = $v.DeviceID.ToUpper()
    $type = switch ([int]$v.DriveType) { 2 { 'removable' } 3 { 'fixed' } 4 { 'network' } 5 { 'optical' } default { 'other' } }
    $b = [string]$bus[$letter]
    $out += [ordered]@{
      letter = $letter; label = [string]$v.VolumeName; type = $type; bus = $b
      sizeBytes = [int64]$v.Size; freeBytes = [int64]$v.FreeSpace
      scanned = ($type -eq 'fixed')                                     # only fixed disks are ever scanned
      excluded = ($Excluded -contains $letter)
      usb = ($b -eq 'USB')                                              # e.g. a USB SSD that reports itself as fixed
      system = ($letter -eq $env:SystemDrive.ToUpper())
    }
  }
  return $out
}

function Test-OnDrives([string]$path, [string[]]$letters) { return ($path.Length -ge 2 -and ($letters -contains $path.Substring(0, 2).ToUpper())) }

# folders where launchers install games, on allowed drives only. covered = every game there is found
# through the launcher itself (Steam libraries, the Xbox app's XboxGames), so adding the folder adds
# nothing. The other launchers' folders are worth scanning too: they find games the launcher has
# forgotten (after a reinstall) or never registered.
function Get-LauncherRoots([string[]]$Excluded) {
  $roots = New-Object System.Collections.ArrayList
  $add = {
    param($launcher, $path)
    if (-not $path) { return }
    $path = ([string]$path).Trim().Trim('"').Replace('/', '\').TrimEnd('\')
    if ($path.Length -lt 3 -or (Test-OnDrives $path $Excluded) -or -not (Test-Path -LiteralPath $path -PathType Container)) { return }
    if (-not @($roots | Where-Object { $_.path -ieq $path }).Count) { [void]$roots.Add([ordered]@{ launcher = $launcher; path = $path; covered = ($launcher -eq 'Steam' -or $launcher -eq 'Xbox app') }) }
  }
  $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if ($steam) {
    $steam = $steam.Replace('/', '\')
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) { $libs += [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value.Replace('\\', '\') } }
    foreach ($l in ($libs | Sort-Object -Unique)) { if (-not (Test-OnDrives $l $Excluded)) { & $add 'Steam' (Join-Path $l 'steamapps\common') } }
  }
  foreach ($m in @(Get-ChildItem (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests\*.item') -ErrorAction SilentlyContinue)) {
    try { $j = [IO.File]::ReadAllText($m.FullName) | ConvertFrom-Json; if ($j.InstallLocation -and -not (Test-OnDrives $j.InstallLocation $Excluded)) { & $add 'Epic Games' (Split-Path $j.InstallLocation) } } catch { }
  }
  foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs' -ErrorAction SilentlyContinue)) {
    $d = (Get-ItemProperty $k.PSPath).InstallDir; if ($d -and -not (Test-OnDrives $d $Excluded)) { & $add 'Ubisoft' (Split-Path $d.TrimEnd('/', '\')) }
  }
  foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue)) {
    $d = (Get-ItemProperty $k.PSPath).path; if ($d -and -not (Test-OnDrives $d $Excluded)) { & $add 'GOG' (Split-Path $d.TrimEnd('\')) }
  }
  foreach ($e in @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)) {
    if (-not $e.InstallLocation -or (Test-OnDrives $e.InstallLocation $Excluded)) { continue }
    if ($e.Publisher -match '^Electronic Arts') { & $add 'EA' (Split-Path $e.InstallLocation.TrimEnd('\')) }
    elseif ($e.Publisher -match '^Blizzard Entertainment' -and $e.DisplayName -notmatch 'Battle\.net') { & $add 'Battle.net' (Split-Path $e.InstallLocation.TrimEnd('\')) }
  }
  foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { $_.DeviceID.ToUpper() })) {
    if ($Excluded -notcontains $d) { & $add 'Xbox app' "$d\XboxGames" }
  }
  return @($roots)
}

# suggested game folders: the current ones, launcher folders that are not fully covered (see above) and
# top-level folders that look like game folders, on fixed drives that are not excluded
function Get-FolderSuggestions([string[]]$Excluded, [string[]]$Current, $LauncherRoots = @()) {
  $re = '(?i)^(games?|my games|pc games|jeux|jeux pc|juegos|jogos|spiele|giochi|gry|igry|oyunlar|steamlibrary|steam library|steam games|epic games|gog games|ea games|ubisoft games|origin games|emulators?|emulation|roms?|repacks?)$|game'
  $out = New-Object System.Collections.ArrayList
  foreach ($c in @($Current)) { if ($c -and -not (Test-OnDrives $c $Excluded)) { [void]$out.Add([ordered]@{ path = ([string]$c).TrimEnd('\'); current = $true }) } }
  foreach ($r in @($LauncherRoots)) {
    if ($r -and -not $r.covered -and -not @($out | Where-Object { $_.path -ieq $r.path }).Count) { [void]$out.Add([ordered]@{ path = $r.path; current = $false }) }
  }
  foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { $_.DeviceID.ToUpper() })) {
    if ($Excluded -contains $d) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath "$d\" -Directory -Force -ErrorAction SilentlyContinue)) {
      if ($f.Name -notmatch $re -or ($f.Attributes -band [IO.FileAttributes]::System) -or $f.Name -match '^(XboxGames|SteamLibrary|Program Files.*|Windows|ProgramData)$') { continue }
      if (-not @($out | Where-Object { $_.path -ieq $f.FullName.TrimEnd('\') }).Count) { [void]$out.Add([ordered]@{ path = $f.FullName.TrimEnd('\'); current = $false }) }
    }
  }
  return @($out)
}

# checks folders typed, picked or pasted from an AI: one result per path
#   ok | missing | excluded | launcher | nested | duplicate | tooBroad | invalid
function Test-FolderList([string[]]$Paths, [string[]]$Excluded, $LauncherRoots) {
  $broad = @("$env:SystemDrive\", $env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Split-Path $env:PUBLIC), $env:USERPROFILE) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }
  $clean = @()
  foreach ($p in @($Paths)) {
    $x = ([string]$p).Trim().Trim('"', "'", '`', ',', ';').Trim()
    if ($x -match '^[A-Za-z]:$') { $x += '\' }
    if ($x.Length -gt 3) { $x = $x.TrimEnd('\') }
    $clean += $x
  }
  $ok = @()
  $res = @()
  foreach ($x in $clean) {
    $status = 'ok'; $why = ''
    if (-not $x -or -not [IO.Path]::IsPathRooted($x) -or $x -notmatch '^[A-Za-z]:\\') { $status = 'invalid' }
    elseif (Test-OnDrives $x $Excluded) { $status = 'excluded' }
    elseif (@($res | Where-Object { $_.path -ieq $x }).Count) { $status = 'duplicate' }
    elseif ($broad -contains $x.TrimEnd('\').ToLowerInvariant()) { $status = 'tooBroad' }
    elseif (-not (Test-Path -LiteralPath $x -PathType Container)) { $status = 'missing' }
    else {
      foreach ($r in @($LauncherRoots)) { if ($r.covered -and ($x -ieq $r.path -or $x.StartsWith($r.path + '\', [StringComparison]::OrdinalIgnoreCase))) { $status = 'launcher'; $why = $r.launcher; break } }
    }
    $res += [ordered]@{ path = $x; status = $status; launcher = $why }
  }
  # a folder inside another accepted folder is already covered by it
  foreach ($r in $res) {
    if ($r.status -ne 'ok') { continue }
    foreach ($o in $res) { if ($o -ne $r -and $o.status -eq 'ok' -and $r.path.StartsWith($o.path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { $r.status = 'nested'; $r.launcher = $o.path; break } }
  }
  return $res
}
