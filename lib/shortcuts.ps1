# Shared by install-shortcuts.ps1 and server.ps1 (Settings > Startup).
# How Game Hub starts a script without a console window:
#   Windows 10 2004+ and Windows 11: conhost.exe --headless (no window, no VBScript)
#   older Windows: wscript.exe + gamehub.vbs (VBScript is being phased out of Windows, so it is only a fallback)

function Get-HiddenStart([string]$Root, [string]$Script) {
  $conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
  $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if ([Environment]::OSVersion.Version.Build -ge 19041 -and (Test-Path $conhost)) {
    return [pscustomobject]@{
      Target    = $conhost
      Arguments = '--headless "' + $ps + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root $Script) + '"'
      Method    = 'conhost'
    }
  }
  $vbsArg = if ($Script -eq 'server.ps1') { ' server' } else { '' }
  return [pscustomobject]@{
    Target    = Join-Path $env:WINDIR 'System32\wscript.exe'
    Arguments = '"' + (Join-Path $Root 'gamehub.vbs') + '"' + $vbsArg
    Method    = 'vbscript'
  }
}

# The shortcut icon is a brand asset: www\brand\icon.ico. gamehub.ico at the root is where it lived
# before (shortcuts made then still point there), used only if the brand icon is missing.
function Get-HubIcon([string]$Root) {
  foreach ($p in @((Join-Path $Root 'www\brand\icon.ico'), (Join-Path $Root 'gamehub.ico'))) { if (Test-Path -LiteralPath $p) { return $p } }
  return $null
}

function New-HubShortcut([string]$Root, [string]$Path, [string]$Script, [string]$Description) {
  $start = Get-HiddenStart $Root $Script
  $wsh = New-Object -ComObject WScript.Shell
  $sc = $wsh.CreateShortcut($Path)
  $sc.TargetPath = $start.Target
  $sc.Arguments = $start.Arguments
  $sc.WorkingDirectory = $Root
  $ico = Get-HubIcon $Root
  if ($ico) { $sc.IconLocation = "$ico,0" }
  $sc.Description = $Description
  $sc.Save()
  return $start.Method
}
