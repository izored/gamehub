#requires -Version 5.1
<#
  Checks the page's translations (www\lang\*.json). Run it after changing text in the page or a
  language file:   powershell -ExecutionPolicy Bypass -File tools\check-translations.ps1

  Errors (exit code 1):
    - a key used by app.js, gamepad.js, pad-advice.js or index.html that is missing from en.json
    - a language file that is not valid JSON, has no _meta, or is not listed in index.json
    - a translation whose {placeholders} differ from the English text
  Warnings:
    - keys a language has not translated yet (English is shown for them), and keys English no longer has
#>
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
$www = Join-Path $Root 'www'
$langDir = Join-Path $www 'lang'
$errors = 0; $warnings = 0
function Fail([string]$m) { $script:errors++; Write-Host "ERROR  $m" -ForegroundColor Red }
function Warn([string]$m) { $script:warnings++; Write-Host "warn   $m" -ForegroundColor Yellow }
function Read-Lang([string]$path) {
  $o = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  $map = @{}
  foreach ($p in $o.PSObject.Properties) { if ($p.Name -ne '_meta') { $map[$p.Name] = [string]$p.Value } }
  return [pscustomobject]@{ meta = $o._meta; keys = $map }
}
function Get-Holes([string]$s) { return @([regex]::Matches($s, '\{(\w+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) }
# plural keys "x.one" / "x.few" / "x.many" / "x.other" all belong to "x"
function Get-Base([string]$k) { return ($k -replace '\.(zero|one|two|few|many|other)$', '') }

$en = Read-Lang (Join-Path $langDir 'en.json')
$enBases = @{}; foreach ($k in $en.keys.Keys) { $enBases[(Get-Base $k)] = $true }

# ---------------------------------------------------------------- keys the page uses
$used = @{}
foreach ($f in 'app.js', 'gamepad.js', 'pad-advice.js') {
  $js = [IO.File]::ReadAllText((Join-Path $www $f))
  foreach ($m in [regex]::Matches($js, "\btn?\('([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)'")) { $used[$m.Groups[1].Value] = $f }
  # keys written as plain strings (toggle messages and similar lists)
  foreach ($m in [regex]::Matches($js, "'((?:toast|err|check|drives|backups|ds4|ask|gp|lang)(?:\.[A-Za-z0-9_]+)+)'")) { $used[$m.Groups[1].Value] = $f }
}
$html = [IO.File]::ReadAllText((Join-Path $www 'index.html'))
foreach ($m in [regex]::Matches($html, 'data-i18n="([^"]+)"')) { $used[$m.Groups[1].Value] = 'index.html' }
foreach ($m in [regex]::Matches($html, 'data-i18n-attr="([^"]+)"')) {
  foreach ($pair in $m.Groups[1].Value.Split(',')) { $used[$pair.Split(':')[1].Trim()] = 'index.html' }
}
# keys built at run time ('err.' + code, 'check.' + status, 'drives.' + type)
foreach ($k in 'err.unknownGame', 'err.exeNotFound', 'err.fileNotFound', 'err.folderNotFound', 'err.excludedDrive', 'err.scanRunning', 'err.nameEmpty',
  'err.exePath', 'err.exeChoose', 'err.insideGame', 'err.schemeNotAllowed', 'err.locked', 'err.imageType', 'err.imageSize', 'err.ds4', 'err.unknownBackup',
  'check.ok', 'check.missing', 'check.excluded', 'check.launcher', 'check.nested', 'check.duplicate', 'check.tooBroad', 'check.invalid', 'check.already',
  'drives.removable', 'drives.network', 'drives.optical', 'drives.fixed', 'drives.otherType') { $used[$k] = 'built at run time' }

foreach ($k in ($used.Keys | Sort-Object)) {
  if (-not $en.keys.ContainsKey($k) -and -not $enBases.ContainsKey($k)) { Fail "en.json has no '$k' (used in $($used[$k]))" }
}
foreach ($k in ($enBases.Keys | Sort-Object)) {
  if (-not $used.ContainsKey($k)) { Warn "en.json key '$k' is not used by the page" }
}

# ---------------------------------------------------------------- every language
$index = [IO.File]::ReadAllText((Join-Path $langDir 'index.json')) | ConvertFrom-Json
$listed = @($index.languages | ForEach-Object { $_.code })
foreach ($file in @(Get-ChildItem -LiteralPath $langDir -Filter *.json | Where-Object { $_.Name -ne 'index.json' })) {
  $code = $file.BaseName
  if ($listed -notcontains $code) { Fail "$($file.Name) is not listed in index.json" }
  try { $lang = Read-Lang $file.FullName } catch { Fail "$($file.Name) is not valid JSON: $($_.Exception.Message)"; continue }
  if (-not $lang.meta -or -not $lang.meta.name) { Fail "$($file.Name) has no _meta.name" }
  if ($code -eq 'en') { continue }
  $missing = @(); $extra = @()
  $bases = @{}; foreach ($k in $lang.keys.Keys) { $bases[(Get-Base $k)] = $true }
  foreach ($k in $en.keys.Keys) {
    $b = Get-Base $k
    if ($k -ne $b) { if (-not $bases.ContainsKey($b)) { $missing += $b } }    # plural: any form of the key counts
    elseif (-not $lang.keys.ContainsKey($k)) { $missing += $k }
  }
  foreach ($k in $lang.keys.Keys) { if (-not $enBases.ContainsKey((Get-Base $k))) { $extra += $k } }
  foreach ($k in $lang.keys.Keys) {
    $ref = $en.keys[$k]
    if ($null -eq $ref) { $ref = $en.keys[(Get-Base $k) + '.other'] }
    if ($null -eq $ref) { continue }
    $a = (Get-Holes $ref) -join ','; $b2 = (Get-Holes $lang.keys[$k]) -join ','
    # a plural form may leave out {n} (for example "one game"), but must not add other placeholders
    if ($a -ne $b2 -and -not ($k -ne (Get-Base $k) -and ((Get-Holes $lang.keys[$k]) | Where-Object { (Get-Holes $ref) -notcontains $_ }).Count -eq 0)) {
      Fail "$($file.Name) '$k' has placeholders {$b2}, English has {$a}"
    }
  }
  $missing = @($missing | Sort-Object -Unique)
  if ($missing.Count) { Warn "$($file.Name): $($missing.Count) not translated yet (shown in English): $(($missing | Select-Object -First 8) -join ', ')$(if ($missing.Count -gt 8) { ', ...' })" }
  if ($extra.Count) { Warn "$($file.Name): $($extra.Count) keys English no longer has: $(($extra | Select-Object -First 8) -join ', ')" }
  Write-Host ("ok     {0,-12} {1} keys{2}" -f $file.Name, $lang.keys.Count, $(if ($lang.meta.machineTranslated) { ', AI-translated' } else { '' }))
}
foreach ($c in $listed) { if (-not (Test-Path -LiteralPath (Join-Path $langDir "$c.json"))) { Fail "index.json lists '$c' but $c.json does not exist" } }

Write-Host ''
Write-Host ("{0} keys used by the page, {1} error(s), {2} warning(s)" -f $used.Count, $errors, $warnings)
if ($errors) { exit 1 }
