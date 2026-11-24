#requires -Version 5.1
<#
  Checks Game Hub before a commit or a release, and makes sure nothing personal goes to GitHub.

    powershell -ExecutionPolicy Bypass -File tools\check-release.ps1           what git would publish
    powershell -ExecutionPolicy Bypass -File tools\check-release.ps1 -Staged   what is staged (the pre-commit hook)

  1. Files that must never be published: config.json, overrides.json, data\, logs\, dist\,
     DATA-MOVED.txt, portable.txt, *.bak, *.damaged, *.zip, session.key, the old root gamehub.ico.
  2. Privacy: no text file may contain anything that points at you or this PC:
     - your Windows user name, this PC's name, your user folder;
     - from your Game Hub data: every game's install folder, your game folders and ignore list, the
       drive labels you excluded or keep games on, your backup copy folder;
     - your Git e-mail, unless it is a GitHub noreply address;
     - every line of release-denylist.txt in your data folder (your own extra words);
     - anything that looks like a secret: GitHub or API tokens, private keys.
     The list is built on this PC each time and never written anywhere. Default install folders
     (Program Files, ProgramData) and generic folders like D:\Games are not on it: they say nothing
     about you, and the docs use them as examples.
  3. The code checks CONTRIBUTING.md asks for: every .ps1 parses in Windows PowerShell 5.1, .ps1 and
     .vbs files are ASCII only, the JavaScript parses (node --check, when Node.js is installed), the
     translations (tools\check-translations.ps1) and the DS4Windows advice tests.
  Exit code 1 when anything fails. With -Staged, the staged files are checked as they are on disk.
#>
param([string]$Root = (Split-Path $PSScriptRoot -Parent), [switch]$Staged)

# the parse check must use Windows PowerShell 5.1, which is what runs Game Hub
if ($PSVersionTable.PSVersion.Major -gt 5) {
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Root', $Root)
  if ($Staged) { $a += '-Staged' }
  & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @a
  exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$script:failed = 0
function Fail([string]$m) { $script:failed++; Write-Host "FAIL   $m" -ForegroundColor Red }
function Pass([string]$m) { Write-Host "ok     $m" -ForegroundColor Green }
function Note([string]$m) { Write-Host "note   $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------- what would be published
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Git is not installed: it decides what gets published'; exit 1 }
$gitArgs = @('-c', 'core.quotepath=off', '-C', $Root)
if ($Staged) {
  $files = @(& git @gitArgs diff --cached --name-only --diff-filter=ACMR)
} elseif (Test-Path -LiteralPath (Join-Path $Root '.git')) {
  $files = @(& git @gitArgs ls-files --cached --others --exclude-standard)
} else {
  # not a repository yet: ask git what a first commit would take, using .gitignore
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('gamehub-check-' + [guid]::NewGuid().ToString('N'))
  [void](& git init -q --bare $tmp)
  $files = @(& git -c core.quotepath=off "--git-dir=$tmp" "--work-tree=$Root" ls-files --others --exclude-standard)
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
$files = @($files | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) } | Sort-Object -Unique)
Write-Host ("Checking {0} file(s){1}" -f $files.Count, $(if ($Staged) { ' staged for commit' } else { ' that would be published' }))
if (-not $files.Count) { Pass 'nothing to check'; exit 0 }

# ---------------------------------------------------------------- 1. files that must stay private
$private = '^(config\.json|overrides\.json|DATA-MOVED\.txt|portable\.txt|gamehub\.ico)$|^(data|logs|dist)/|\.(bak|damaged|zip)$|(^|/)session\.key$'
$bad = @($files | Where-Object { $_ -match $private })
if ($bad.Count) { foreach ($f in $bad) { Fail "$f is personal or generated and must not be published (check .gitignore)" } }
else { Pass 'no settings, data, logs or backups in the list' }

# ---------------------------------------------------------------- 2. privacy
. (Join-Path $Root 'lib\paths.ps1')
$dataRoot = Get-HubDataRoot $Root
$deny = New-Object System.Collections.Generic.List[object]
$genericWords = @('admin', 'administrator', 'administrateur', 'administrador', 'user', 'owner', 'guest', 'gamer', 'pc',
  'windows', 'system', 'os', 'data', 'games', 'local disk', 'disque local', 'recovery', 'new volume', 'nouveau nom', 'backup', 'storage', 'ssd', 'hdd')
# a drive, Program Files or a launcher's default folder, or a folder like D:\Games: the same on
# every PC. A game's own folder, or anything you named yourself, is not generic.
$launcherDirs = '(Epic Games(\\Launcher)?|EA Games|Origin Games|Steam(\\steamapps\\common)?|Ubisoft(\\Ubisoft Game Launcher(\\games)?)?|GOG Galaxy(\\Games)?|GOG Games|Rockstar Games|Riot Games|Battle\.net|Amazon Games(\\Library)?|WindowsApps|ModifiableWindowsApps|XboxGames|Microsoft Games)'
function Test-GenericPath([string]$p) {
  $p = $p.TrimEnd('\')
  if ($p -match '^[A-Za-z]:$') { return $true }
  if ($p -match ('^[A-Za-z]:\\(Program Files( \(x86\))?|ProgramData)(\\' + $launcherDirs + ')?$')) { return $true }
  if ($p -match ('^[A-Za-z]:\\((Games|Jeux|Spiele|Juegos|Giochi|SteamLibrary)(\\steamapps\\common)?|' + $launcherDirs + ')$')) { return $true }
  return $false
}
function Add-Word([string]$text, [string]$why, [int]$min = 3) {
  if (-not $text) { return }
  $t = $text.Trim()
  if ($t.Length -lt $min -or $genericWords -contains $t.ToLowerInvariant()) { return }
  $deny.Add([pscustomobject]@{ Text = $t; Why = $why; Word = $true })
}
function Add-PathText([string]$text, [string]$why) {
  if (-not $text) { return }
  $t = $text.Trim().TrimEnd('\')
  if ($t.Length -lt 4 -or $t -notmatch '^[A-Za-z]:\\' -or (Test-GenericPath $t)) { return }
  $deny.Add([pscustomobject]@{ Text = $t; Why = $why; Word = $false })
}
function Read-JsonFile([string]$p) { if (Test-Path -LiteralPath $p) { try { return ([IO.File]::ReadAllText($p) | ConvertFrom-Json) } catch { } }; return $null }
# every text value of a JSON object, however deep
function Get-JsonStrings($o) {
  if ($null -eq $o) { return }
  if ($o -is [string]) { $o; return }
  if ($o -is [System.Collections.IEnumerable]) { foreach ($x in $o) { Get-JsonStrings $x }; return }
  if ($o.PSObject) { foreach ($pr in $o.PSObject.Properties) { if ($pr.MemberType -eq 'NoteProperty') { Get-JsonStrings $pr.Value } } }
}

Add-Word $env:USERNAME 'your Windows user name'
Add-Word $env:COMPUTERNAME "this PC's name"
Add-PathText $env:USERPROFILE 'your user folder'
$cfg = Read-JsonFile (Join-Path $dataRoot 'config.json')
if ($cfg) {
  foreach ($s in @(Get-JsonStrings $cfg)) { if ($s -match '^[A-Za-z]:\\') { Add-PathText $s 'a folder in your settings' } }
  foreach ($l in @($cfg.excludeVolumeLabels)) { Add-Word ([string]$l) 'a drive label in your settings' 2 }
  foreach ($i in @($cfg.ignore)) { if ($i -and ([string]$i) -notmatch '^[A-Za-z]:\\') { Add-Word ([string]$i) 'an entry of your ignore list' } }
}
$ov = Read-JsonFile (Join-Path $dataRoot 'overrides.json')
foreach ($s in @(Get-JsonStrings $ov)) { if ($s -match '^[A-Za-z]:\\') { Add-PathText $s 'a path in your fixes (overrides.json)' } }
$cat = Read-JsonFile (Join-Path $dataRoot 'data\games.json')
$plain = @()
if ($cat) {
  foreach ($g in @($cat.games)) { Add-PathText ([string]$g.installDir) "the install folder of $($g.name)" }
  foreach ($c in @($cat.cleanup)) { Add-PathText ([string]$c.path) 'a folder in your clean-up list' }
  # a label made of letters only ("cache", "Media") is an ordinary word all over the code, and says
  # nothing about you; one like "X5" or "WD_Black 2TB" does
  foreach ($d in @($cat.drives)) {
    $l = ([string]$d.label).Trim()
    if (-not $l) { continue }
    if ($l -match '^[\p{L} ]+$') { $plain += $l } else { Add-Word $l "the label of drive $($d.letter)" 2 }
  }
}
$mail = (& git config user.email 2>$null)
if ($mail -and $mail -notmatch '@users\.noreply\.github\.com$') { Add-Word $mail 'your Git e-mail' }
$extra = Join-Path $dataRoot 'release-denylist.txt'
if (Test-Path -LiteralPath $extra) { foreach ($l in [IO.File]::ReadAllLines($extra)) { if ($l.Trim() -and -not $l.Trim().StartsWith('#')) { Add-Word $l 'a line of your release-denylist.txt' 2 } } }

$seen = @{}
$rules = @(foreach ($d in $deny) {
  $k = $d.Text.ToLowerInvariant(); if ($seen[$k]) { continue }; $seen[$k] = $true
  $rx = [regex]::Escape($d.Text)
  if ($d.Word) { $rx = '(?<![\w])' + $rx + '(?![\w])' }
  [pscustomobject]@{ Rx = New-Object regex ($rx, 'IgnoreCase'); Why = $d.Why; Text = $d.Text }
})
$secrets = @(
  @('gh[pousr]_[A-Za-z0-9]{30,}', 'a GitHub token'), @('github_pat_[A-Za-z0-9_]{30,}', 'a GitHub token'),
  @('\bsk-[A-Za-z0-9_-]{20,}', 'an API key'), @('-----BEGIN [A-Z ]*PRIVATE KEY-----', 'a private key'),
  @('\bAKIA[0-9A-Z]{16}\b', 'an AWS key'), @('\bxox[baprs]-[A-Za-z0-9-]{10,}', 'a Slack token'))
$textExt = '\.(ps1|psm1|vbs|js|json|html|css|svg|md|txt|yml|yaml|xml|cmd|bat|sh)$|^\.[a-z]+$|(^|/)\.[a-z]+$|(^|/)[A-Za-z-]+$'
$hits = 0; $scanned = 0
foreach ($f in $files) {
  if ($f -notmatch $textExt) { continue }
  $scanned++
  $lines = [IO.File]::ReadAllLines((Join-Path $Root $f))
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    foreach ($r in $rules) { if ($r.Rx.IsMatch($line)) { $hits++; Fail ("{0}:{1}  {2}: {3}" -f $f, ($i + 1), $r.Why, $r.Text) } }
    foreach ($s in $secrets) { if ($line -match $s[0]) { $hits++; Fail ("{0}:{1}  looks like {2}" -f $f, ($i + 1), $s[1]) } }
  }
}
if (-not $hits) { Pass ("no personal details or secrets in {0} text file(s) ({1} things checked)" -f $scanned, $rules.Count) }
if (-not $cfg) { Note "no Game Hub data found in $dataRoot, so only your user name, PC name and secrets were checked" }
$plain = @($plain | Where-Object { $_ -and $genericWords -notcontains $_.ToLowerInvariant() } | Sort-Object -Unique)
if ($plain.Count -and -not $Staged) { Note ("drive labels that are plain words were not searched for: " + ($plain -join ', ') + ". Add one to $extra to search for it too") }
$images = @($files | Where-Object { $_ -match '\.(jpg|jpeg|png|webp|gif|ico)$' })
if ($images.Count -and -not $Staged) { Note ("pictures are not scanned, look at them yourself: " + ($images -join ', ')) }

# ---------------------------------------------------------------- 3. code checks
$ps = @($files | Where-Object { $_ -match '\.ps1$' })
$parseBad = 0
foreach ($f in $ps) {
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $f), [ref]$null, [ref]$errs)
  if ($errs) { $parseBad++; Fail ("{0} does not parse in Windows PowerShell 5.1: {1}" -f $f, (($errs | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ')) }
}
if ($ps.Count -and -not $parseBad) { Pass ("{0} PowerShell file(s) parse in Windows PowerShell 5.1" -f $ps.Count) }

$asciiBad = 0
foreach ($f in @($files | Where-Object { $_ -match '\.(ps1|vbs)$' })) {
  $b = [IO.File]::ReadAllBytes((Join-Path $Root $f))
  for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -gt 127) { $asciiBad++; Fail "$f has a non-ASCII character (byte $i); build it with [char]0x.... instead"; break } }
}
if (-not $asciiBad) { Pass 'PowerShell and VBScript files are ASCII only' }

$node = Get-Command node -ErrorAction SilentlyContinue
$js = @($files | Where-Object { $_ -match '\.js$' })
if (-not $node) { if ($js.Count) { Note 'Node.js is not installed: JavaScript syntax and the advice tests were not checked' } }
else {
  $jsBad = 0
  foreach ($f in $js) { $out = & node --check (Join-Path $Root $f) 2>&1; if ($LASTEXITCODE -ne 0) { $jsBad++; Fail "$f does not parse: $(($out | Select-Object -First 3) -join ' ')" } }
  if ($js.Count -and -not $jsBad) { Pass ("{0} JavaScript file(s) parse" -f $js.Count) }
  $test = Join-Path $Root 'tools\test-pad-advice.js'
  if (-not $Staged -or @($files | Where-Object { $_ -match '^(www/pad-advice\.js|tools/test-pad-advice\.js)$' }).Count) {
    if (Test-Path -LiteralPath $test) { $out = & node $test 2>&1; if ($LASTEXITCODE -ne 0) { Fail ('DS4Windows advice tests: ' + (($out | Where-Object { $_ -match 'FAIL' }) -join '; ')) } else { Pass 'DS4Windows advice tests' } }
  }
}

if (-not $Staged -or @($files | Where-Object { $_ -match '^www/' }).Count) {
  $out = & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\check-translations.ps1') -Root $Root 2>&1
  if ($LASTEXITCODE -ne 0) { Fail ('translations: ' + (($out | Where-Object { $_ -match 'ERROR' } | Select-Object -First 5) -join '; ')) } else { Pass 'translations' }
}

Write-Host ''
if ($script:failed) {
  Write-Host "$($script:failed) problem(s). Nothing was changed; fix them and run this again." -ForegroundColor Red
  if ($Staged) { Write-Host 'The commit was stopped. If a privacy hit is really fine to publish, commit with --no-verify.' -ForegroundColor Red }
  exit 1
}
Write-Host 'All good.' -ForegroundColor Green
exit 0
