#requires -Version 5.1
<#
  Builds a Game Hub release zip from Git, so only committed files ship: never your settings or data.

    powershell -ExecutionPolicy Bypass -File tools\make-release.ps1 -Version 1.1.0
    powershell -ExecutionPolicy Bypass -File tools\make-release.ps1 -Version 1.1.0 -Publish

  Before building, it checks that:
    - nothing is left uncommitted (the zip is the last commit, exactly);
    - CHANGELOG.md has a "## [1.1.0]" section: its text becomes the release notes;
    - www\brand\about.json shows the same version (Settings > Made by);
    - tools\check-release.ps1 passes (privacy scan and code checks).
  It writes dist\GameHub-<version>.zip (one GameHub folder inside), its SHA-256 checksum and the
  release notes. dist\ is not in Git. .github and .githooks are left out of the zip (.gitattributes).

  -Publish also creates the GitHub release v<version> with the zip and checksum attached, using the
  GitHub CLI (gh, signed in). The last commit must be pushed first. Nothing is published without it.
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Root = '',
  [switch]$Publish
)

$ErrorActionPreference = 'Stop'
function Stop-Release([string]$m) { Write-Host "STOP   $m" -ForegroundColor Red; exit 1 }
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }   # (Windows PowerShell 5.1 has no $PSScriptRoot in this param block)
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { Stop-Release "'$Version' is not a version like 1.2.0" }
if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { Stop-Release "$Root is not a Git repository" }
$git = @('-C', $Root)

# 1. the zip must be exactly the last commit
$dirty = @(& git @git status --porcelain)
if ($dirty.Count) { Stop-Release ("uncommitted changes, commit or stash them first:`n       " + ($dirty -join "`n       ")) }
$head = (& git @git rev-parse HEAD).Trim()

# 2. release notes from the changelog
$log = [IO.File]::ReadAllText((Join-Path $Root 'CHANGELOG.md'))
$m = [regex]::Match($log, '(?ms)^## \[' + [regex]::Escape($Version) + '\][^\r\n]*\r?\n(.*?)(?=^## \[|^\[[^\]]+\]: |\z)')
if (-not $m.Success -or -not $m.Groups[1].Value.Trim()) { Stop-Release "CHANGELOG.md has no '## [$Version]' section yet: rename [Unreleased] to [$Version] - $((Get-Date).ToString('yyyy-MM-dd')) and commit" }
$notes = $m.Groups[1].Value.Trim()
# the version Settings > Made by shows
$about = [IO.File]::ReadAllText((Join-Path $Root 'www\brand\about.json')) | ConvertFrom-Json
if ([string]$about.version -ne $Version) { Stop-Release "www\brand\about.json says version '$($about.version)': set it to $Version and commit" }

# 3. privacy scan and code checks
& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\check-release.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { Stop-Release 'tools\check-release.ps1 found problems' }

# 4. build
$dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "GameHub-$Version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
& git @git archive --format=zip --prefix=GameHub/ -o $zip $head
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zip)) { Stop-Release 'git archive failed' }
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$shaFile = "$zip.sha256"
[IO.File]::WriteAllText($shaFile, "$hash  GameHub-$Version.zip`n")
$notesFile = Join-Path $dist "notes-$Version.md"
[IO.File]::WriteAllText($notesFile, $notes + "`n`nSHA-256 of GameHub-$Version.zip: ``$hash```n", (New-Object Text.UTF8Encoding $false))
$size = [math]::Round((Get-Item -LiteralPath $zip).Length / 1KB)
Write-Host ''
Write-Host "Built  $zip ($size KB) from commit $($head.Substring(0, 7))" -ForegroundColor Green
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
try { & gh release create "v$Version" $zip $shaFile --title "Game Hub $Version" --notes-file $notesFile --target $head }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { Stop-Release 'gh release create failed' }
Write-Host "Published release v$Version" -ForegroundColor Green
