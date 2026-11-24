#requires -Version 5.1
# One-time setup: creates three shortcuts with the Game Hub icon (www\brand\icon.ico)
#   Desktop\Game Hub.lnk          open the hub
#   Start Menu\Game Hub.lnk       open the hub (findable from Windows search / Start11)
#   Startup\Game Hub Server.lnk   start the server hidden at logon (single-instance, safe to run twice)
# The shortcuts start PowerShell without a window through "conhost --headless" (Windows 10 2004+ and 11),
# or through gamehub.vbs on older Windows (see lib\shortcuts.ps1).
# Re-running it just refreshes the shortcuts (and moves old VBScript shortcuts to the new way).
# The icon is a brand asset: replace www\brand\icon.ico with your own and re-run this. The default
# one is drawn below only when that file is missing.
param([string]$Root = $PSScriptRoot)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)
Add-Type -AssemblyName System.Drawing
$cfgPath = Join-Path $Data 'config.json'
if (-not (Test-Path -LiteralPath $cfgPath)) { $cfgPath = Join-Path $Root 'config.example.json' }   # before the first start
$port = ([IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json).port

function New-HubPng([int]$s) {
  $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
  $f = $s / 64.0
  $rect = New-Object System.Drawing.RectangleF 0, 0, $s, $s
  $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
  $r = 15 * $f; $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddArc(0, 0, 2 * $r, 2 * $r, 180, 90); $p.AddArc($s - 2 * $r, 0, 2 * $r, 2 * $r, 270, 90)
  $p.AddArc($s - 2 * $r, $s - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc(0, $s - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure()
  $g.FillPath($bg, $p)
  # controller body: rounded top bar + two grips
  $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 14, 14, 14))
  $body = New-Object System.Drawing.Drawing2D.GraphicsPath
  $body.AddArc(9 * $f, 21 * $f, 22 * $f, 22 * $f, 180, 90); $body.AddArc(33 * $f, 21 * $f, 22 * $f, 22 * $f, 270, 90)
  $body.AddLine(55 * $f, 32 * $f, 56 * $f, 42 * $f); $body.AddLine(9 * $f, 42 * $f, 8 * $f, 32 * $f); $body.CloseFigure()
  $g.FillPath($white, $body)
  $g.FillEllipse($white, 7 * $f, 30 * $f, 17 * $f, 18 * $f); $g.FillEllipse($white, 40 * $f, 30 * $f, 17 * $f, 18 * $f)
  $g.FillRectangle($white, 16 * $f, 32 * $f, 32 * $f, 10.5 * $f)
  $ink = [System.Drawing.Brushes]::White
  $g.FillRectangle($ink, 19.5 * $f, 27.5 * $f, 3 * $f, 11 * $f); $g.FillRectangle($ink, 15.5 * $f, 31.5 * $f, 11 * $f, 3 * $f)
  $g.FillEllipse($ink, 39.9 * $f, 27.4 * $f, 5.2 * $f, 5.2 * $f)
  $g.FillEllipse($ink, 44.9 * $f, 32.4 * $f, 5.2 * $f, 5.2 * $f)
  $g.Dispose()
  $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  return , $ms.ToArray()
}

# .ico with PNG-compressed frames (supported since Vista)
function New-HubIco([string]$Path) {
  $sizes = 256, 64, 48, 32, 16
  $frames = foreach ($sz in $sizes) { , (New-HubPng $sz) }
  $ico = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ico
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
  $offset = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$d); $w.Write([byte]$d); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$frames[$i].Length); $w.Write([uint32]$offset)
    $offset += $frames[$i].Length
  }
  foreach ($fr in $frames) { $w.Write($fr) }
  $w.Flush()
  [IO.File]::WriteAllBytes($Path, $ico.ToArray())
}
$icoPath = Join-Path $Root 'www\brand\icon.ico'
if (-not (Test-Path -LiteralPath $icoPath)) {
  [void](New-Item -ItemType Directory -Force (Split-Path $icoPath))
  New-HubIco $icoPath
  Write-Host "Drew the default icon: $icoPath"
}

. (Join-Path $Root 'lib\shortcuts.ps1')
function New-Shortcut([string]$lnk, [string]$script, [string]$desc) {
  $how = New-HubShortcut $Root $lnk $script $desc
  Write-Host "Created $lnk ($(if ($how -eq 'conhost') { 'hidden console' } else { 'VBScript fallback' }))"
}
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Game Hub.lnk') 'open-hub.ps1' 'Open Game Hub - all installed games in one place'
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Game Hub.lnk') 'open-hub.ps1' 'Open Game Hub - all installed games in one place'
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Startup')) 'Game Hub Server.lnk') 'server.ps1' "Starts the Game Hub local server (http://localhost:$port)"
