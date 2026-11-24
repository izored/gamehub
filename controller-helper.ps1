#requires -Version 5.1
<#
  "Bring Game Hub back" with a controller (Settings > Controllers, controllerSummon in config.json,
  on by default). Started hidden by server.ps1.
  Hold View + Menu on an Xbox controller (Share + Options on a PlayStation controller through
  DS4Windows) for 1.5 seconds, anywhere in Windows: Game Hub comes to the front, or opens if it was
  closed. It reads controllers through XInput, so it works with Xbox controllers and with anything that
  appears as one (DS4Windows, Steam Input). A DualSense or DualShock 4 connected directly, without
  DS4Windows, is not seen by XInput.
  -Test brings Game Hub to the front once and exits (no controller needed).
#>
param([string]$Root = $PSScriptRoot, [switch]$Test)
. (Join-Path $Root 'lib\paths.ps1')
$Data = Initialize-HubData $Root   # your settings and data, apart from the program (lib\paths.ps1)

$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'lib\windows.ps1')
$logFile = Join-Path $Data 'logs\watch.log'
function Write-Log([string]$msg) { try { [IO.File]::AppendAllText($logFile, ('{0}  controller: {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg, [Environment]::NewLine)) } catch { } }

function Invoke-Summon {
  $hubs = Get-HubWindows
  if ($hubs.Count) {
    $front = [GameHubWindows]::BringToFront($hubs[0].Handle)
    Write-Log "Game Hub brought back (in front: $front)"
  } else {
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process $ps -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Root 'open-hub.ps1') + '"')
    Write-Log 'Game Hub was closed: opening it'
  }
}

if ($Test) { Invoke-Summon; exit 0 }

$mutex = New-Object System.Threading.Mutex($false, 'Local\GameHubControllerHelper')
if (-not $mutex.WaitOne(0)) { exit 0 }

if (-not ('GameHubXInput' -as [type])) {
  Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class GameHubXInput {
  [StructLayout(LayoutKind.Sequential)] public struct Pad { public ushort Buttons; public byte LeftTrigger; public byte RightTrigger; public short LX, LY, RX, RY; }
  [StructLayout(LayoutKind.Sequential)] public struct State { public uint Packet; public Pad Gamepad; }
  [DllImport("xinput1_4.dll")] public static extern uint XInputGetState(uint index, out State state);
}
'@
}

$BACK = 0x0020; $START = 0x0010
$cfgPath = Join-Path $Data 'config.json'
$heldSince = $null; $waitRelease = $false; $nextCfg = Get-Date
Write-Log 'started (hold View + Menu for 1.5 s)'
while ($true) {
  if ((Get-Date) -ge $nextCfg) {
    $nextCfg = (Get-Date).AddSeconds(30)
    try { $c = [IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json; if ($c.PSObject.Properties['controllerSummon'] -and -not $c.controllerSummon) { break } } catch { }
  }
  $any = $false; $combo = $false
  for ($i = 0; $i -lt 4; $i++) {
    $s = New-Object GameHubXInput+State
    if ([GameHubXInput]::XInputGetState($i, [ref]$s) -eq 0) {
      $any = $true
      if (($s.Gamepad.Buttons -band ($BACK -bor $START)) -eq ($BACK -bor $START)) { $combo = $true }
    }
  }
  if ($combo) {
    if (-not $heldSince) { $heldSince = Get-Date }
    elseif (-not $waitRelease -and ((Get-Date) - $heldSince).TotalMilliseconds -ge 1500) {
      try { Invoke-Summon } catch { Write-Log "error: $($_.Exception.Message)" }
      $waitRelease = $true
    }
  } else { $heldSince = $null; $waitRelease = $false }
  Start-Sleep -Milliseconds $(if ($any) { 60 } else { 1500 })
}
Write-Log 'stopped (option switched off)'
