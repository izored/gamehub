#requires -Version 5.1
<#
  Builds a Game Hub release zip from Git, so only committed files ship: never your settings or data.

    powershell -ExecutionPolicy Bypass -File tools\make-release.ps1 -Version 1.1.0 -Title "Every game on your PC, in one place" -NotesOnly
    powershell -ExecutionPolicy Bypass -File tools\make-release.ps1 -Version 1.1.0 -Title "Every game on your PC, in one place"
    powershell -ExecutionPolicy Bypass -File tools\make-release.ps1 -Version 1.1.0 -Title "Every game on your PC, in one place" -Publish

  The release page is the changelog: its "## [1.1.0]" section, word for word, becomes the release
  notes, with the zip's SHA-256 added under the heading. So write the changelog for the people who will
  read the release page (a headline sentence and plain words per change), and use full https://
  links: a release page cannot follow links relative to the repository. -Title is the one-line
  headline: the release is called "Game Hub v1.1.0 - <title>".

  -NotesOnly writes dist\notes-<version>.md to preview, and stops there: nothing else is checked.

  Before building, it checks that:
    - nothing is left uncommitted (the zip is the last commit, exactly);
    - CHANGELOG.md has the version's section, with no relative links;
    - www\brand\about.json shows the same version (Settings > Made by);
    - tools\check-release.ps1 passes (privacy scan and code checks).
  It writes dist\GameHub-<version>.zip (one GameHub folder inside), its SHA-256 checksum and the
  release notes. dist\ is not in Git. .github and .githooks are left out of the zip (.gitattributes).

  -Publish also creates the GitHub release v<version> with the zip and checksum attached, using the
  GitHub CLI (gh, signed in). The last commit must be pushed first. Nothing is published without it.
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Title = '',
  [string]$Root = '',
  [switch]$NotesOnly,
  [switch]$Publish
)

$ErrorActionPreference = 'Stop'
function Stop-Release([string]$m) { Write-Host "STOP   $m" -ForegroundColor Red; exit 1 }
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }   # (Windows PowerShell 5.1 has no $PSScriptRoot in this param block)
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { Stop-Release "'$Version' is not a version like 1.2.0" }
$name = "Game Hub v$Version"
if ($Title.Trim()) { $name += ' ' + [char]0x2014 + ' ' + $Title.Trim() }
$utf8 = New-Object Text.UTF8Encoding $false
$dist = Join-Path $Root 'dist'

# the release notes: the version's changelog section, heading included
function Get-ReleaseNotes {
  $log = [IO.File]::ReadAllText((Join-Path $Root 'CHANGELOG.md'))
  $m = [regex]::Match($log, '(?ms)^(## \[' + [regex]::Escape($Version) + '\][^\r\n]*)\r?\n(.*?)(?=^## \[|^\[[^\]]+\]: |\z)')
  if (-not $m.Success -or -not $m.Groups[2].Value.Trim()) { Stop-Release "CHANGELOG.md has no '## [$Version]' section yet: rename [Unreleased] to [$Version] - $((Get-Date).ToString('yyyy-MM-dd')) and commit" }
  $text = $m.Groups[1].Value + "`n`n" + $m.Groups[2].Value.Trim()
  $relative = @([regex]::Matches($text, '\]\((?!https?://|#|mailto:)([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if ($relative.Count) { Stop-Release ("the $Version section links to files by relative path, which a release page cannot follow. Use full https://github.com/... links for: " + ($relative -join ', ')) }
  return $text
}
# the checksum goes right under the version heading, so it's at the top of the release page
function Write-Notes([string]$notes, [string]$hash) {
  New-Item -ItemType Directory -Force -Path $dist | Out-Null
  $file = Join-Path $dist "notes-$Version.md"
  $line = "> **GameHub-$Version.zip** SHA-256: ``$hash`` (to check your download: ``Get-FileHash .\GameHub-$Version.zip``)"
  $nl = $notes.IndexOf("`n")
  $text = $notes.Substring(0, $nl) + "`n`n" + $line + "`n" + $notes.Substring($nl)
  [IO.File]::WriteAllText($file, ($text.TrimEnd() + "`n").Replace("`r`n", "`n"), $utf8)
  return $file
}

if ($NotesOnly) {
  $file = Write-Notes (Get-ReleaseNotes) '(filled in when the zip is built)'
  Write-Host "Release   $name"
  Write-Host "Notes     $file"
  exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { Stop-Release "$Root is not a Git repository" }
$git = @('-C', $Root)

# 1. the zip must be exactly the last commit
$dirty = @(& git @git status --porcelain)
if ($dirty.Count) { Stop-Release ("uncommitted changes, commit or stash them first:`n       " + ($dirty -join "`n       ")) }
$head = (& git @git rev-parse HEAD).Trim()

# 2. release notes, and the version Settings > Made by shows
$notes = Get-ReleaseNotes
$about = [IO.File]::ReadAllText((Join-Path $Root 'www\brand\about.json')) | ConvertFrom-Json
if ([string]$about.version -ne $Version) { Stop-Release "www\brand\about.json says version '$($about.version)': set it to $Version and commit" }

# 3. privacy scan and code checks
& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\check-release.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { Stop-Release 'tools\check-release.ps1 found problems' }

# 4. build
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "GameHub-$Version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
& git @git archive --format=zip --prefix=GameHub/ -o $zip $head
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zip)) { Stop-Release 'git archive failed' }
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$shaFile = "$zip.sha256"
[IO.File]::WriteAllText($shaFile, "$hash  GameHub-$Version.zip`n")
$notesFile = Write-Notes $notes $hash
$size = [math]::Round((Get-Item -LiteralPath $zip).Length / 1KB)
Write-Host ''
Write-Host "Built  $zip ($size KB) from commit $($head.Substring(0, 7))" -ForegroundColor Green
Write-Host "       release $name"
Write-Host "       SHA-256 $hash"
Write-Host "       notes   $notesFile"

if (-not $Publish) {
  Write-Host ''
  Write-Host "To publish it as GitHub release v${Version}: push this commit, then run this again with -Publish."
  exit 0
}

# 5. publish
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Stop-Release 'the GitHub CLI (gh) is not installed' }
[void](& git @git fetch --quiet origin)
$pushed = @(& git @git branch -r --contains $head)
if (-not $pushed.Count) { Stop-Release "commit $($head.Substring(0, 7)) is not on GitHub yet: push it first" }
Push-Location $Root   # gh finds the repository from the folder's origin remote
try { & gh release create "v$Version" $zip $shaFile --title $name --notes-file $notesFile --target $head }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { Stop-Release 'gh release create failed' }
Write-Host "Published $name" -ForegroundColor Green
