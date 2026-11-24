# Optional lock (config.json "lockToAccount": true, Settings > Security):
# only the Windows account that runs Game Hub can use it. Off by default; offered when the PC has
# other user accounts.
#   - data\session.key holds a random key that only this account (plus SYSTEM and administrators)
#     can read.
#   - open-hub.ps1 opens http://localhost:<port>/?k=<key>; the server swaps the key for a cookie
#     (HttpOnly, SameSite=Strict) and every API, artwork and export request must carry it.
#   - Another account can load the page but every action is refused (401, code "locked").

function Get-LockKeyPath([string]$Data) { return (Join-Path $Data 'data\session.key') }

function Get-LockKey([string]$Data) {
  $p = Get-LockKeyPath $Data
  if (Test-Path -LiteralPath $p) { try { return ([IO.File]::ReadAllText($p)).Trim() } catch { } }
  return $null
}

function New-LockKey([string]$Data) {
  $bytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($bytes); $rng.Dispose()
  $key = -join ($bytes | ForEach-Object { $_.ToString('x2') })
  $p = Get-LockKeyPath $Data
  [IO.File]::WriteAllText($p, $key)
  $acl = New-Object Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true, $false)                                  # no inherited "Users: read"
  $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
  foreach ($sid in @($me, (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'), (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))) {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')))
  }
  [IO.File]::SetAccessControl($p, $acl)                                       # .NET call: works even where Set-Acl's module cannot load
  return $key
}

# other enabled accounts on this PC (built-in Guest, DefaultAccount and WDAGUtilityAccount are ignored)
function Get-OtherAccounts {
  return @(Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True AND Disabled=False' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $env:USERNAME -and $_.SID -notmatch '-(501|503|504)$' } | ForEach-Object Name)
}

function Test-LockCookie($req, [string]$key) {
  if (-not $key) { return $false }
  $c = $req.Cookies['gh_key']
  return [bool]($c -and $c.Value -eq $key)
}

function Set-LockCookie($ctx, [string]$key) {
  $ctx.Response.AppendHeader('Set-Cookie', "gh_key=$key; Path=/; HttpOnly; SameSite=Strict")
}
