#requires -Version 5.1
<#
  Game Hub scanner - builds data\games.json and data\art\* .

  Sources, in priority order (first one to claim an install folder wins):
    1. Launcher records   Steam app manifests, Epic launcher manifests, Ubisoft Connect registry,
                          GOG Galaxy registry, Battle.net / Amazon Games uninstall entries, Riot Client
                          install files, Rockstar Games registry, Xbox app / Microsoft Store packages
                          (MicrosoftGame.config); Steam's own play time comes from localconfig.vdf
    2. Declared folders   every sub-folder of config.gameRoots that contains a game executable
    3. Discovery          uninstall-registry folders + sub-folders of config.discoverRoots that
                          contain game-engine files (steam_api, Unity, Unreal .pak, Bink, FMOD, ...)
  Only fixed local disks are read; drives listed in config.excludeDriveLetters / excludeVolumeLabels never are.
  Manual fixes (names, exe, hide, duplicates, cleanup notes) live in overrides.json.

  Re-run any time:  powershell -NoProfile -ExecutionPolicy Bypass -File scan-games.ps1
#>
param([string]$Root = $PSScriptRoot, [switch]$NoCovers)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

$ErrorActionPreference = 'Continue'
$started = Get-Date
$dataDir = Join-Path $Data 'data'
$artDir  = Join-Path $dataDir 'art'
New-Item -ItemType Directory -Force -Path $artDir, (Join-Path $Data 'logs') | Out-Null
try { Start-Transcript -Path (Join-Path $Data 'logs\scan.log') -Force | Out-Null } catch { }
$utf8 = New-Object System.Text.UTF8Encoding $false

function Read-Json([string]$path) {
  if (Test-Path -LiteralPath $path) { return ([IO.File]::ReadAllText($path) | ConvertFrom-Json) }
  return $null
}

if (-not (Test-Path (Join-Path $Data 'config.json'))) { Copy-Item (Join-Path $Root 'config.example.json') (Join-Path $Data 'config.json') }   # first run
$cfg = Read-Json (Join-Path $Data 'config.json')
$ovr = Read-Json (Join-Path $Data 'overrides.json')
$ovGames = @{}
if ($ovr -and $ovr.games) { foreach ($p in $ovr.games.PSObject.Properties) { $ovGames[$p.Name] = $p.Value } }

# ---------------------------------------------------------------- native helpers
if (-not ('GameHubNative' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class GameHubNative {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint PrivateExtractIcons(string file, int idx, int cx, int cy, IntPtr[] icons, uint[] ids, uint n, uint flags);
  [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetIconInfo(IntPtr h, out ICONINFO info);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
  [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int size, out BITMAP bm);
  [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, [Out] byte[] bits, ref BITMAPINFOHEADER bmi, uint usage);
  [StructLayout(LayoutKind.Sequential)] struct ICONINFO { public bool fIcon; public int x; public int y; public IntPtr hbmMask; public IntPtr hbmColor; }
  [StructLayout(LayoutKind.Sequential)] struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public ushort bmPlanes, bmBitsPixel; public IntPtr bmBits; }
  [StructLayout(LayoutKind.Sequential)] struct BITMAPINFOHEADER { public int biSize, biWidth, biHeight; public ushort biPlanes, biBitCount; public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant; }

  static byte[] Bits(IntPtr hdc, IntPtr hbm, int w, int h) {
    BITMAPINFOHEADER bi = new BITMAPINFOHEADER();
    bi.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER)); bi.biWidth = w; bi.biHeight = -h; bi.biPlanes = 1; bi.biBitCount = 32;
    byte[] buf = new byte[w * h * 4];
    return GetDIBits(hdc, hbm, 0, (uint)h, buf, ref bi, 0) == 0 ? null : buf;
  }

  // Extracts the exe's main icon at `size` px as a PNG with real alpha. Returns false if the exe has no icon.
  public static bool SaveIcon(string exe, string png, int size) {
    IntPtr[] hs = new IntPtr[1]; uint[] ids = new uint[1];
    uint n = PrivateExtractIcons(exe, 0, size, size, hs, ids, 1, 0);
    if (n == 0 || n == 0xFFFFFFFF || hs[0] == IntPtr.Zero) return false;
    IntPtr hdc = GetDC(IntPtr.Zero);
    ICONINFO ii = new ICONINFO();
    try {
      if (!GetIconInfo(hs[0], out ii) || ii.hbmColor == IntPtr.Zero) return false;
      BITMAP bm; GetObject(ii.hbmColor, Marshal.SizeOf(typeof(BITMAP)), out bm);
      int w = bm.bmWidth, h = bm.bmHeight;
      byte[] c = Bits(hdc, ii.hbmColor, w, h);
      if (c == null) return false;
      bool alpha = false;
      for (int i = 3; i < c.Length; i += 4) { if (c[i] != 0) { alpha = true; break; } }
      if (!alpha) {
        byte[] m = Bits(hdc, ii.hbmMask, w, h);
        for (int i = 0; i < c.Length; i += 4) c[i + 3] = (byte)((m != null && m[i] != 0) ? 0 : 255);
      }
      using (Bitmap b = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
        BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        for (int y = 0; y < h; y++) Marshal.Copy(c, y * w * 4, IntPtr.Add(d.Scan0, y * d.Stride), w * 4);
        b.UnlockBits(d);
        b.Save(png, ImageFormat.Png);
      }
      return true;
    } finally {
      if (ii.hbmColor != IntPtr.Zero) DeleteObject(ii.hbmColor);
      if (ii.hbmMask != IntPtr.Zero) DeleteObject(ii.hbmMask);
      ReleaseDC(IntPtr.Zero, hdc);
      DestroyIcon(hs[0]);
    }
  }

  // Total bytes under a folder; skips junctions/symlinks and unreadable entries.
  public static long DirSize(string path) {
    long total = 0;
    Stack<string> stack = new Stack<string>(); stack.Push(path);
    while (stack.Count > 0) {
      string d = stack.Pop();
      try { foreach (string f in Directory.EnumerateFiles(d)) { try { total += new FileInfo(f).Length; } catch { } } } catch { }
      try {
        foreach (string s in Directory.EnumerateDirectories(d)) {
          try { if ((File.GetAttributes(s) & FileAttributes.ReparsePoint) == 0) stack.Push(s); } catch { }
        }
      } catch { }
    }
    return total;
  }
}
'@
}

# ---------------------------------------------------------------- drives
$allowedDrives = @{}
$driveInfo = @()
foreach ($v in Get-CimInstance Win32_LogicalDisk) {
  $letter = $v.DeviceID.ToUpper()
  $isExcluded = ($cfg.excludeDriveLetters -contains $letter) -or ($v.VolumeName -and ($cfg.excludeVolumeLabels -contains $v.VolumeName)) -or ($v.DriveType -ne 3)
  if (-not $isExcluded) {
    $allowedDrives[$letter] = $true
    $driveInfo += [pscustomobject]@{ letter = $letter; label = "$($v.VolumeName)"; totalBytes = [int64]$v.Size; freeBytes = [int64]$v.FreeSpace }
  }
}

function Norm([string]$p) {
  if (-not $p) { return '' }
  $p = $p.Trim().Trim('"').Replace('/', '\')
  try { $p = [IO.Path]::GetFullPath($p) } catch { }
  return $p.TrimEnd('\').ToLowerInvariant()
}
function Test-Allowed([string]$p) {
  if (-not $p -or $p.Length -lt 2) { return $false }
  return $allowedDrives.ContainsKey($p.Substring(0, 2).ToUpper())
}
function Get-Slug([string]$s) { return (($s.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')) }

$rootsNorm  = @($cfg.gameRoots | ForEach-Object { Norm $_ })
$ignoreNorm = @($cfg.ignore    | ForEach-Object { Norm $_ })
function Test-Ignored([string]$n) {
  foreach ($i in $ignoreNorm) { if ($n -eq $i -or $n.StartsWith($i + '\')) { return $true } }
  return $false
}

# ---------------------------------------------------------------- name + exe heuristics
$TM = [string][char]0x2122; $REG = [string][char]0x00AE; $COPY = [string][char]0x00A9
function Get-CleanName([string]$n) {
  if (-not $n) { return '' }
  $n = $n.Replace($TM, '').Replace($REG, '').Replace($COPY, '')
  $n = $n -replace '\s+(version\s+[\d.]+.*|v\d+(\.\d+)+.*)$', ''
  return (($n -replace '\s{2,}', ' ').Trim())
}
function Get-PrettyFolder([string]$n) { return (($n -creplace '(?<=[a-z])(?=[A-Z])', ' ') -replace '[_]+', ' ').Trim() }
function Get-Alnum([string]$s) { return ($s.ToLowerInvariant() -replace '[^a-z0-9]', '') }

$ExeSkip = '^(unins|uninst|setup|install|vc_?redist|vcredist|dxsetup|dxwebsetup|dotnet|ndp\d|ue\dprereq|ueprereq|crash|crs-|bugsplat|quicksfv|pbsvc|pnkbstr|patchprogress|activation|touchup|cleanup|eosbootstrapper|easyanticheat|eaanticheat\.installer|beservice|battleye|cefsharp|cefprocess|.*webhelper|.*overlay|ffmpeg|ffprobe|7z|unitycrashhandler|notification_helper|support|perf_graph|console\.|d3d11install|nvprofilefixer|.*redist|launcherpatcher|.*updater|update|report|link2ea|dxdiag|agrepack)'
$DirSkip = '^(_?redist|_commonredist|commonredist|__installer|installer|support|crack|directx|dotnet|vcredist|easyanticheat|battleye|_overlay|language packs|prereq.*|engine|_uninstall|uninstall|d3d11installer)$'

function Find-GameExe([string]$dir, [string]$hint) {
  $base = (Get-Item -LiteralPath $dir -Force).FullName.TrimEnd('\')
  # EA titles ship their real launch command in __Installer\installerdata.xml
  $ea = Join-Path $base '__Installer\installerdata.xml'
  if (Test-Path -LiteralPath $ea) {
    $x = [IO.File]::ReadAllText($ea)
    $ms = @([regex]::Matches($x, '<filePath>\s*\[[^\]]+\]([^<]+?\.exe)\s*</filePath>', 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value.Replace('/', '\') })
    foreach ($rel in (@($ms | Where-Object { $_ -notmatch 'trial' }) + @($ms | Where-Object { $_ -match 'trial' }))) {
      $p = Join-Path $base $rel
      if (Test-Path -LiteralPath $p) { return $p }
    }
  }
  $h = Get-Alnum $hint
  $cands = Get-ChildItem -LiteralPath $base -Recurse -Depth 4 -File -Filter *.exe -Force -ErrorAction SilentlyContinue | Where-Object {
    if ($_.Length -lt 100KB -or $_.Name -match $ExeSkip) { return $false }
    $rel = $_.DirectoryName.Substring($base.Length).Trim('\')
    if ($rel) { foreach ($seg in $rel.Split('\')) { if ($seg -match $DirSkip) { return $false } } }
    return $true
  }
  $best = $cands | Sort-Object `
    @{ Expression = { ($_.DirectoryName.Substring($base.Length).Split('\') | Where-Object { $_ }).Count } }, `
    @{ Expression = { $e = Get-Alnum $_.BaseName; if ($e -eq $h) { 2 } elseif ($h -and $e -and ($h.Contains($e) -or $e.Contains($h))) { 1 } else { 0 } }; Descending = $true }, `
    @{ Expression = { $_.Length }; Descending = $true } | Select-Object -First 1
  if ($best) { return $best.FullName }
  return $null
}

$GameFiles = @('steam_api.dll','steam_api64.dll','unityplayer.dll','gameassembly.dll','eossdk-win64-shipping.dll','eossdk-win32-shipping.dll',
  'bink2w64.dll','binkw64.dll','binkw32.dll','bink2w32.dll','fmod.dll','fmod64.dll','fmodex64.dll','fmodstudio.dll','fmodstudio64.dll',
  'nvngx_dlss.dll','libxess.dll','sl.interposer.dll','amd_ags_x64.dll','galaxy64.dll','galaxy.dll','uplay_r1_loader64.dll','upc_r2_loader64.dll',
  'discord_game_sdk.dll','physx3_x64.dll','physx_64.dll')
function Test-GameSignature([string]$dir) {
  $hit = Get-ChildItem -LiteralPath $dir -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue | Where-Object {
    ($_.PSIsContainer -and $_.Name -match '^(EasyAntiCheat|BattlEye)$') -or
    (-not $_.PSIsContainer -and (($GameFiles -contains $_.Name.ToLowerInvariant()) -or ($_.Extension -eq '.pak' -and $_.Directory.Name -eq 'Paks')))
  } | Select-Object -First 1
  return [bool]$hit
}
$DenyFolder = '^(Common Files|WindowsApps|ModifiableWindowsApps|Windows.*|Microsoft.*|Internet Explorer|Reference Assemblies|MSBuild|dotnet|PowerShell|Steam|Epic Games|Ubisoft|Electronic Arts|EA Games|Origin|Origin Games|GOG Galaxy|Battle\.net|Riot.*|Rockstar Games|Amazon Games|NVIDIA.*|Intel|AMD|Realtek|Google|Mozilla.*|Adobe|Maxon.*|OTOY|Fender|Native Instruments|Spectrasonics|Applied Acoustics Systems|Plex.*|Jellyfin|Sonarr|Radarr|Lidarr|Prowlarr|Git|nodejs|Python.*|Docker|JetBrains|Denuvo Anti-Cheat|Sony|Uninstall Information|Embark Studios.*|Parsec)$'
$DenyPublisher = 'Microsoft|NVIDIA|Maxon|OTOY|Fender|Adobe|Serif|Native Instruments|Spectrasonics|Valve|Epic Games, Inc|GOG\.com|Discord|Parsec|Streamlabs|Telegram|Zoom|Perplexity'

# ---------------------------------------------------------------- uninstall registry
$regEntries = @{}
$regKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
foreach ($e in (Get-ItemProperty $regKeys -ErrorAction SilentlyContinue)) {
  if (-not $e.DisplayName -or -not $e.InstallLocation) { continue }
  $n = Norm $e.InstallLocation
  if ($n -and -not $regEntries.ContainsKey($n)) { $regEntries[$n] = $e }
}
function Get-RegDate($e) {
  if ($e -and "$($e.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$') { return (Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3]).Date }
  return $null
}

# ---------------------------------------------------------------- collection
$games   = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$seen    = @{}   # normalized install dir -> id
$ids     = @{}

function Test-Claimed([string]$n) {
  if ($seen.ContainsKey($n)) { return $true }
  foreach ($s in $seen.Keys) { if ($n.StartsWith($s + '\') -or $s.StartsWith($n + '\')) { return $true } }
  return $false
}

function Add-Game {
  param([string]$Source, [string]$IdBase, [string]$Name, [string]$Dir, [string]$Exe, [string]$LaunchUri,
        [int64]$Size = 0, [datetime]$Installed = [datetime]::MinValue, $LastPlayed = $null, [string]$Header = '', [string]$Warning = '',
        [string]$Cover = '', [string]$Hero = '', [string]$Logo = '', [string]$LaunchArgs = '',
        [string]$LaunchExe = '', [string]$StoreId = '', [int]$SteamMinutes = 0)
  $n = Norm $Dir
  if (Test-Claimed $n) { return }
  $id = $IdBase; $k = 2
  while ($ids.ContainsKey($id)) { $id = "$IdBase-$k"; $k++ }
  $o = $ovGames[$id]
  if ($o -and $o.hidden) { $seen[$n] = $id; $ids[$id] = $true; return }
  if ($o -and $o.exe) { $Exe = if ([IO.Path]::IsPathRooted($o.exe)) { $o.exe } else { Join-Path $Dir $o.exe } }
  if ($o -and $o.name) { $Name = $o.name }
  $seen[$n] = $id; $ids[$id] = $true

  $info = Get-Item -LiteralPath $Dir -Force
  if ($Size -le 0) { $Size = [GameHubNative]::DirSize($info.FullName) }
  if ($Installed -eq [datetime]::MinValue) { $Installed = $info.CreationTime }

  # art: Steam header if we have one, plus the exe icon (fallback: largest exe in the folder)
  $iconFile = ''
  $png = Join-Path $artDir "$id.png"
  $tryExes = @()
  if ($Exe) { $tryExes += $Exe }
  $tryExes += (Get-ChildItem -LiteralPath $info.FullName -Filter *.exe -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $ExeSkip } | Sort-Object Length -Descending | Select-Object -First 2 | ForEach-Object FullName)
  foreach ($t in $tryExes) { try { if ([GameHubNative]::SaveIcon($t, $png, 256)) { $iconFile = "$id.png"; break } } catch { } }
  $copyArt = {
    param($src, $kind)
    if ($src -and (Test-Path -LiteralPath $src)) {
      $f = "$id-$kind" + [IO.Path]::GetExtension($src).ToLowerInvariant()
      Copy-Item -LiteralPath $src -Destination (Join-Path $artDir $f) -Force
      return $f
    }
    return ''
  }
  $headerFile = & $copyArt $Header 'header'
  $coverFile  = & $copyArt $Cover 'cover'
  $heroFile   = & $copyArt $Hero 'hero'
  $logoFile   = & $copyArt $Logo 'logo'

  # an executable chosen in the hub (overrides.json) wins over the launcher URI
  $argsVal = if ($o -and $o.args) { [string]$o.args } else { $LaunchArgs }
  $launch = if ($o -and $o.uri) { [ordered]@{ type = 'uri'; target = $o.uri } }
            elseif ($o -and $o.exe -and $Exe) { [ordered]@{ type = 'exe'; target = $Exe; args = $argsVal } }
            elseif ($LaunchUri) { [ordered]@{ type = 'uri'; target = $LaunchUri } }
            elseif ($LaunchExe) { [ordered]@{ type = 'exe'; target = $LaunchExe; args = $argsVal } }   # e.g. Riot Client with --launch-product
            elseif ($Exe) { [ordered]@{ type = 'exe'; target = $Exe; args = $argsVal } }
            else { $null }
  if (-not $launch) { [void]$skipped.Add([pscustomobject]@{ path = $info.FullName; reason = 'No launchable executable'; sizeBytes = $Size }); return }

  [void]$games.Add([pscustomobject][ordered]@{
    id          = $id
    name        = $Name
    source      = $Source
    drive       = $info.FullName.Substring(0, 2).ToUpper()
    installDir  = $info.FullName
    exe         = $Exe
    launch      = $launch
    sizeBytes   = $Size
    installedAt = $Installed.ToString('s')
    lastPlayed  = $(if ($LastPlayed) { ([datetime]$LastPlayed).ToString('s') } else { $null })
    icon        = $iconFile
    header      = $headerFile
    cover       = $coverFile
    hero        = $heroFile
    logo        = $logoFile
    defaultUri  = $LaunchUri
    customExe   = [bool]($o -and $o.exe)
    manual      = $Source -eq 'manual' -or $id.StartsWith('manual-')
    warning     = $(if ($o -and $o.warning) { $o.warning } else { $Warning })
    note        = $(if ($o -and $o.note) { $o.note } else { '' })
    duplicateOf = $(if ($o -and $o.duplicateOf) { $o.duplicateOf } else { '' })
    storeId     = $StoreId
    steamMinutes = $SteamMinutes
  })
  Write-Host ("  + {0,-12} {1}" -f $Source, $Name)
}

# 1a. Steam --------------------------------------------------------------
Write-Host 'Steam...'
$steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
# Steam's own play time (minutes) per app, from every Steam account's localconfig.vdf on this PC
function Get-VdfBlock([string]$text, [string]$key, [int]$from = 0) {
  $m = [regex]::new('"' + [regex]::Escape($key) + '"\s*\{', 'IgnoreCase').Match($text, $from)
  if (-not $m.Success) { return $null }
  $depth = 0; $start = $m.Index + $m.Length - 1
  for ($i = $start; $i -lt $text.Length; $i++) {
    if ($text[$i] -eq '{') { $depth++ } elseif ($text[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($start + 1, $i - $start - 1) } }
  }
  return $null
}
function Get-SteamPlaytime([string]$steamRoot) {
  $play = @{}
  foreach ($lc in @(Get-ChildItem (Join-Path $steamRoot 'userdata\*\config\localconfig.vdf') -ErrorAction SilentlyContinue)) {
    try {
      $t = [IO.File]::ReadAllText($lc.FullName)
      $steam = Get-VdfBlock $t 'Steam'
      $apps = if ($steam) { Get-VdfBlock $steam 'apps' } else { $null }
      if (-not $apps) { continue }
      foreach ($m in [regex]::Matches($apps, '"(\d+)"\s*\{')) {
        $block = Get-VdfBlock $apps $m.Groups[1].Value $m.Index
        if (-not $block) { continue }
        $pt = [regex]::Match($block, '"Playtime"\s+"(\d+)"')
        if ($pt.Success) { $v = [int]$pt.Groups[1].Value; $id = $m.Groups[1].Value; if (-not $play.ContainsKey($id) -or $v -gt $play[$id]) { $play[$id] = $v } }
      }
    } catch { Write-Host "  could not read $($lc.FullName): $($_.Exception.Message)" }
  }
  return $play
}

if ($steamPath) {
  $steamPath = $steamPath.Replace('/', '\')
  $steamPlay = Get-SteamPlaytime $steamPath
  $libs = @($steamPath)
  $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
  if (Test-Path $vdf) { $libs += [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value.Replace('\\', '\') } }
  foreach ($lib in ($libs | Sort-Object -Unique)) {
    if (-not (Test-Allowed $lib)) { continue }
    foreach ($m in Get-ChildItem (Join-Path $lib 'steamapps\appmanifest_*.acf') -ErrorAction SilentlyContinue) {
      $t = [IO.File]::ReadAllText($m.FullName)
      $appid = [regex]::Match($t, '"appid"\s+"(\d+)"').Groups[1].Value
      $name  = [regex]::Match($t, '"name"\s+"([^"]+)"').Groups[1].Value
      $idir  = [regex]::Match($t, '"installdir"\s+"([^"]+)"').Groups[1].Value
      if ($appid -eq '228980' -or $name -match 'Redistributable|Steamworks|Proton|Steam Linux Runtime') { continue }
      $dir = Join-Path $lib "steamapps\common\$idir"
      if (-not (Test-Path -LiteralPath $dir)) { [void]$skipped.Add([pscustomobject]@{ path = $dir; reason = "Steam manifest for '$name' but folder is missing"; sizeBytes = 0 }); continue }
      $lp = [regex]::Match($t, '"LastPlayed"\s+"(\d+)"').Groups[1].Value
      $last = if ($lp -and $lp -ne '0') { [DateTimeOffset]::FromUnixTimeSeconds([int64]$lp).LocalDateTime } else { $null }
      $size = [int64]([regex]::Match($t, '"SizeOnDisk"\s+"(\d+)"').Groups[1].Value)
      $lc = Join-Path $steamPath "appcache\librarycache\$appid"
      $lcFiles = @(Get-ChildItem -LiteralPath $lc -Recurse -File -ErrorAction SilentlyContinue)
      $pick = { param([string[]]$names) foreach ($n in $names) { $f = $lcFiles | Where-Object Name -eq $n | Select-Object -First 1; if ($f) { return $f.FullName } }; return '' }
      $hdr = & $pick @('library_header.jpg', 'header.jpg')
      if (-not $hdr) { $hdr = Join-Path $steamPath "appcache\librarycache\${appid}_header.jpg" }
      Add-Game -Source 'steam' -IdBase "steam-$appid" -Name (Get-CleanName $name) -Dir $dir -Exe (Find-GameExe $dir $name) `
        -LaunchUri "steam://rungameid/$appid" -Size $size -LastPlayed $last -Header $hdr -SteamMinutes ([int]$steamPlay[$appid]) `
        -Cover (& $pick @('library_600x900_2x.jpg', 'library_600x900.jpg')) -Hero (& $pick @('library_hero.jpg')) -Logo (& $pick @('logo.png'))
    }
  }
}

# 1b. Epic (registered with the launcher) ---------------------------------
Write-Host 'Epic...'
foreach ($m in Get-ChildItem (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests\*.item') -ErrorAction SilentlyContinue) {
  $j = [IO.File]::ReadAllText($m.FullName) | ConvertFrom-Json
  if ($j.bIsIncompleteInstall -or ($j.MainGameAppName -and $j.MainGameAppName -ne $j.AppName)) { continue }
  $dir = $j.InstallLocation
  if (-not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
  $exe = Join-Path $dir $j.LaunchExecutable.Replace('/', '\')
  if (-not (Test-Path -LiteralPath $exe)) { $exe = Find-GameExe $dir $j.DisplayName }
  $uri = 'com.epicgames.launcher://apps/{0}%3A{1}%3A{2}?action=launch&silent=true' -f $j.CatalogNamespace, $j.CatalogItemId, $j.AppName
  Add-Game -Source 'epic' -IdBase ('epic-' + (Get-Slug (Split-Path $dir -Leaf))) -Name (Get-CleanName $j.DisplayName) -Dir $dir -Exe $exe -LaunchUri $uri
}

# 1c. Ubisoft Connect -------------------------------------------------------
Write-Host 'Ubisoft...'
foreach ($k in Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs' -ErrorAction SilentlyContinue) {
  $dir = (Get-ItemProperty $k.PSPath).InstallDir
  if (-not $dir) { continue }
  $dir = $dir.Replace('/', '\').TrimEnd('\')
  if (-not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
  $re = $regEntries[(Norm $dir)]
  $name = if ($re) { Get-CleanName $re.DisplayName } else { Split-Path $dir -Leaf }
  Add-Game -Source 'ubisoft' -IdBase "ubi-$($k.PSChildName)" -Name $name -Dir $dir -Exe (Find-GameExe $dir $name) `
    -LaunchUri "uplay://launch/$($k.PSChildName)/0" -Installed $(if (Get-RegDate $re) { Get-RegDate $re } else { [datetime]::MinValue })
}

# 1d. GOG Galaxy (registry; GOG games have no DRM, so they start from their own program) ------
Write-Host 'GOG...'
foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue)) {
  $v = Get-ItemProperty $k.PSPath
  $dir = ([string]$v.path).TrimEnd('\')
  if (-not $dir -or -not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
  $name = if ($v.gameName) { Get-CleanName $v.gameName } else { Split-Path $dir -Leaf }
  $exe = if ($v.exe -and (Test-Path -LiteralPath $v.exe)) { [string]$v.exe } else { Find-GameExe $dir $name }
  $gogArgs = if ($v.launchParam) { [string]$v.launchParam } else { '' }
  Add-Game -Source 'gog' -IdBase "gog-$($k.PSChildName)" -Name $name -Dir $dir -Exe $exe -LaunchArgs $gogArgs `
    -Installed $(if (Get-RegDate $regEntries[(Norm $dir)]) { Get-RegDate $regEntries[(Norm $dir)] } else { [datetime]::MinValue })
}

# 1e. Battle.net (Blizzard uninstall entries; known games start through a battlenet:// link) -------
Write-Host 'Battle.net...'
$bnetCodes = @{ prometheus = 'Pro'; fenris = 'Fen'; wow = 'WoW'; wow_classic = 'WoWC'; diablo3 = 'D3'; hs_beta = 'WTCG'; heroes = 'Hero'; s2 = 'S2'; s1 = 'S1'; w3 = 'W3'; osi = 'OSI' }
foreach ($e in @(Get-ItemProperty $regKeys -ErrorAction SilentlyContinue | Where-Object { $_.Publisher -match '^Blizzard Entertainment' -and $_.DisplayName -notmatch 'Battle\.net' -and $_.InstallLocation })) {
  $dir = $e.InstallLocation.Trim().Trim('"').TrimEnd('\')
  if (-not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
  $uid = if ("$($e.UninstallString)" -match '--uid=([A-Za-z0-9_]+)') { $Matches[1].ToLowerInvariant() } else { '' }
  $code = $bnetCodes[$uid]
  $name = Get-CleanName $e.DisplayName
  Add-Game -Source 'battlenet' -IdBase ('bnet-' + $(if ($uid) { $uid } else { Get-Slug $name })) -Name $name -Dir $dir -Exe (Find-GameExe $dir $name) `
    -LaunchUri $(if ($code) { "battlenet://$code" } else { '' }) -Installed $(if (Get-RegDate $e) { Get-RegDate $e } else { [datetime]::MinValue })
}

# 1f. Riot Client (League of Legends, VALORANT, ...) ------------------------------------------------
Write-Host 'Riot...'
$riotInstalls = Read-Json (Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json')
$riotClient = if ($riotInstalls -and $riotInstalls.rc_default) { ([string]$riotInstalls.rc_default).Replace('/', '\') } else { '' }
$riotNames = @{ league_of_legends = 'League of Legends'; valorant = 'VALORANT'; bacon = 'Legends of Runeterra'; lion = '2XKO' }
foreach ($ps in @(Get-ChildItem (Join-Path $env:ProgramData 'Riot Games\Metadata\*\*.product_settings.yaml') -ErrorAction SilentlyContinue)) {
  $t = [IO.File]::ReadAllText($ps.FullName)
  $dir = [regex]::Match($t, 'product_install_full_path:\s*"?([^"\r\n]+)"?').Groups[1].Value.Replace('/', '\').TrimEnd('\')
  if (-not $dir -or -not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir) -or -not $riotClient -or -not (Test-Path -LiteralPath $riotClient)) { continue }
  $parts = $ps.Directory.Name -split '\.', 2              # league_of_legends.live
  $product = $parts[0]; $patch = if ($parts.Count -gt 1) { $parts[1] } else { 'live' }
  $name = if ($riotNames[$product]) { $riotNames[$product] } else { Get-PrettyFolder ($product -replace '_', ' ') }
  Add-Game -Source 'riot' -IdBase "riot-$product" -Name $name -Dir $dir -Exe (Find-GameExe $dir $name) `
    -LaunchExe $riotClient -LaunchArgs "--launch-product=$product --launch-patchline=$patch"
}

# 1g. Amazon Games (uninstall entries; start through an amazon-games:// link) -----------------------
Write-Host 'Amazon Games...'
foreach ($e in @(Get-ItemProperty $regKeys -ErrorAction SilentlyContinue | Where-Object { "$($_.UninstallString)" -match 'Amazon Game Remover' -and $_.InstallLocation })) {
  $dir = $e.InstallLocation.Trim().Trim('"').TrimEnd('\')
  if (-not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
  $pid2 = if ("$($e.UninstallString)" -match '-p\s+"?([A-Za-z0-9-]+)') { $Matches[1] } else { '' }
  $name = Get-CleanName $e.DisplayName
  Add-Game -Source 'amazon' -IdBase ('amazon-' + (Get-Slug $name)) -Name $name -Dir $dir -Exe (Find-GameExe $dir $name) `
    -LaunchUri $(if ($pid2) { "amazon-games://play/$pid2" } else { '' })
}

# 1h. Rockstar Games Launcher (registry; the game's own program hands over to the launcher) -----------
Write-Host 'Rockstar...'
foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Rockstar Games' -ErrorAction SilentlyContinue)) {
  $dir = ([string](Get-ItemProperty $k.PSPath).InstallFolder).TrimEnd('\')
  if (-not $dir -or $k.PSChildName -match 'Launcher|Social Club' -or -not (Test-Allowed $dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
  $name = Get-CleanName $k.PSChildName
  Add-Game -Source 'rockstar' -IdBase ('rockstar-' + (Get-Slug $name)) -Name $name -Dir $dir -Exe (Find-GameExe $dir $name)
}

# 1i. Xbox app / Game Pass / Microsoft Store games (packages with a MicrosoftGame.config) ------------
Write-Host 'Xbox app / Microsoft Store...'
foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation -and -not $_.IsFramework })) {
  $cfgFile = Join-Path $p.InstallLocation 'MicrosoftGame.config'
  if (-not (Test-Path -LiteralPath $cfgFile)) { continue }
  $dir = ([string]$p.InstallLocation).TrimEnd('\')
  if (-not (Test-Allowed $dir)) { continue }
  try { $mg = [xml][IO.File]::ReadAllText($cfgFile) } catch { continue }
  $name = [string]$mg.Game.ShellVisuals.DefaultDisplayName
  if (-not $name -or $name -like 'ms-resource*') { $name = [string]$mg.Game.Identity.Name }
  $exeName = @($mg.Game.ExecutableList.Executable)[0].Name
  $exe = if ($exeName -and (Test-Path -LiteralPath (Join-Path $dir $exeName))) { Join-Path $dir $exeName } else { Find-GameExe $dir $name }
  $appId = try { @((Get-AppxPackageManifest $p).Package.Applications.Application)[0].Id } catch { 'Game' }
  $store = [string]$mg.Game.StoreId
  Add-Game -Source 'xbox' -IdBase ('xbox-' + (Get-Slug $name)) -Name (Get-CleanName $name) -Dir $dir -Exe $exe `
    -LaunchUri "shell:AppsFolder\$($p.PackageFamilyName)!$appId" -StoreId $store
}

# 2 + 3. Folder candidates ----------------------------------------------------
function Resolve-Candidate([string]$dir, [bool]$needSignature) {
  $n = Norm $dir
  if (-not (Test-Allowed $dir) -or (Test-Ignored $n) -or ($rootsNorm -contains $n) -or (Test-Claimed $n)) { return }
  foreach ($r in $rootsNorm) { if ($r.StartsWith($n + '\')) { return } }           # a folder that contains a game root
  $leaf = Split-Path $dir -Leaf
  if ($leaf.StartsWith('.') -or $leaf.StartsWith('$') -or $leaf -match '(?i)redist$|^(System Volume Information|Windows|Recovery|Config\.Msi|PerfLogs)$') { return }
  if ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::System) { return }
  $re = $regEntries[$n]
  if ($needSignature) {
    if ($leaf -match $DenyFolder) { return }
    if ($re -and $re.Publisher -match $DenyPublisher) { return }
    if (-not (Test-GameSignature $dir)) { return }
  }
  $isEpic = Test-Path -LiteralPath (Join-Path $dir '.egstore')
  $isEa   = (Test-Path -LiteralPath (Join-Path $dir '__Installer\installerdata.xml')) -or ($re -and $re.Publisher -match 'Electronic Arts')
  $source = if ($isEpic) { 'epic' } elseif ($isEa) { 'ea' } else { 'other' }
  $name = ''
  if ($re) { $name = Get-CleanName $re.DisplayName }
  $exe = Find-GameExe $dir $(if ($name) { $name } else { $leaf })
  if (-not $exe) {
    [void]$skipped.Add([pscustomobject]@{ path = $dir; reason = 'No game executable found'; sizeBytes = [GameHubNative]::DirSize($dir) })
    return
  }
  if (-not $name) {
    $pn = (Get-Item -LiteralPath $exe).VersionInfo.ProductName
    if ($pn -and $pn.Trim() -notmatch '^(BootstrapPackagedGame.*|Unreal.*|UE[45].*|Unity.*|.*Epic Games.*|Microsoft.*|Windows.*|Game|Launcher)$') { $name = Get-CleanName $pn }
    else { $name = Get-PrettyFolder $leaf }
  }
  $warn = if ($isEpic) { 'Not registered in the Epic launcher - starts directly from its exe. If it asks for Epic, re-link it in Epic: Library > the game > Install, and choose the folder above this game''s folder as the install location.' } else { '' }
  Add-Game -Source $source -IdBase ("$source-" + (Get-Slug $leaf)) -Name $name -Dir $dir -Exe $exe `
    -Installed $(if (Get-RegDate $re) { Get-RegDate $re } else { [datetime]::MinValue }) -Warning $warn
}

Write-Host 'Declared game folders...'
foreach ($r in $cfg.gameRoots) {
  if (-not (Test-Path -LiteralPath $r) -or -not (Test-Allowed $r)) { continue }
  foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue) { Resolve-Candidate $d.FullName $false }
}

Write-Host 'Discovery (registry + Program Files)...'
foreach ($n in @($regEntries.Keys)) {
  $p = $regEntries[$n].InstallLocation.Trim().Trim('"').Replace('/', '\').TrimEnd('\')
  if ($p -and (Test-Path -LiteralPath $p -PathType Container)) { Resolve-Candidate $p $true }
}
foreach ($r in $cfg.discoverRoots) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue) { Resolve-Candidate $d.FullName $true }
}

# manual additions ------------------------------------------------------------
if ($ovr -and $ovr.add) {
  foreach ($a in $ovr.add) {
    if (-not $a.dir -or -not (Test-Path -LiteralPath $a.dir) -or -not (Test-Allowed $a.dir)) { continue }
    $exe = if ($a.exe) { if ([IO.Path]::IsPathRooted($a.exe)) { $a.exe } else { Join-Path $a.dir $a.exe } } else { Find-GameExe $a.dir $a.name }
    Add-Game -Source $(if ($a.source) { $a.source } else { 'other' }) -IdBase $(if ($a.id) { $a.id } else { 'manual-' + (Get-Slug $a.name) }) -Name $a.name -Dir $a.dir -Exe $exe -LaunchUri $a.uri -LaunchArgs ([string]$a.args)
  }
}

# cleanup notes (leftovers, duplicates the scanner cannot know about) ---------
$cleanup = New-Object System.Collections.ArrayList
if ($ovr -and $ovr.cleanup) {
  foreach ($c in $ovr.cleanup) {
    if (-not (Test-Path -LiteralPath $c.path) -or -not (Test-Allowed $c.path)) { continue }
    [void]$cleanup.Add([pscustomobject][ordered]@{ path = $c.path; title = $c.title; note = $c.note; keep = $c.keep; sizeBytes = [GameHubNative]::DirSize($c.path) })
  }
}

# ---------------------------------------------------------------- write
$byDrive = @{}
foreach ($g in $games) { if (-not $g.duplicateOf) { if (-not $byDrive[$g.drive]) { $byDrive[$g.drive] = @(0, [int64]0) }; $byDrive[$g.drive][0]++; $byDrive[$g.drive][1] += $g.sizeBytes } }
$drives = foreach ($d in ($driveInfo | Sort-Object letter)) {
  $x = $byDrive[$d.letter]
  [pscustomobject][ordered]@{ letter = $d.letter; label = $d.label; totalBytes = $d.totalBytes; freeBytes = $d.freeBytes
    games = $(if ($x) { $x[0] } else { 0 }); gameBytes = $(if ($x) { $x[1] } else { 0 }) }
}

$out = [ordered]@{
  generatedAt    = (Get-Date).ToString('s')
  scanSeconds    = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
  newDays        = $cfg.newDays
  excludedDrives = @($cfg.excludeDriveLetters)
  drives         = @($drives)
  games          = @($games | Sort-Object name)
  cleanup        = @($cleanup)
  skipped        = @($skipped)
}
$json = ConvertTo-Json -InputObject $out -Depth 8
$tmp = Join-Path $dataDir 'games.json.tmp'
[IO.File]::WriteAllText($tmp, $json, $utf8)
Move-Item -LiteralPath $tmp -Destination (Join-Path $dataDir 'games.json') -Force
Write-Host ("Done: {0} games, {1} skipped, {2}s" -f $games.Count, $skipped.Count, $out.scanSeconds)
if (-not $NoCovers) {
  Write-Host 'Covers (Steam artwork for games that have none yet)...'
  try { & (Join-Path $Root 'fetch-covers.ps1') -Root $Root } catch { Write-Host "Cover fetch failed: $($_.Exception.Message)" }
}
try { Stop-Transcript | Out-Null } catch { }
