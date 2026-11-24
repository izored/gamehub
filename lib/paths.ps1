# Where Game Hub keeps your data, apart from the program:
#   config.json      your settings
#   overrides.json   your fixes: names, executables, hidden games, duplicates
#   data\            the game list, favorites, play time, artwork, backups, controller answers
#   logs\            what the scripts did
# By default that is %LOCALAPPDATA%\GameHub: the program folder then holds nothing personal, can
# live anywhere (even Program Files), and an update can replace it whole. Each Windows account gets
# its own data. Two ways to keep it elsewhere:
#   portable.txt   an empty file of that name next to server.ps1 keeps the data in the program
#                  folder itself: a copy on a USB drive, or a development copy that must not share
#                  your everyday hub's data
#   GAMEHUB_DATA   an environment variable naming the data folder (tests)
#
# Older versions kept all of this next to the scripts. The first start after updating copies it to
# the data folder: see Initialize-HubData. The originals are left where they were.

function Get-HubDataRoot([string]$AppRoot) {
  if ($env:GAMEHUB_DATA) { return [IO.Path]::GetFullPath($env:GAMEHUB_DATA).TrimEnd('\') }
  if ($AppRoot -and (Test-Path -LiteralPath (Join-Path $AppRoot 'portable.txt'))) { return [IO.Path]::GetFullPath($AppRoot).TrimEnd('\') }
  return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GameHub')
}

# The note left in the program folder after its data was copied out. While it is there, the old
# files are never copied again (say, after you delete the data folder to start over).
$script:HubMovedNote = 'DATA-MOVED.txt'

# Returns the data folder, ready to use. Every script calls this first, so whichever starts first
# after an update does the copy (once: a lock keeps two scripts from doing it at the same time).
function Initialize-HubData([string]$AppRoot) {
  $data = Get-HubDataRoot $AppRoot
  $app = [IO.Path]::GetFullPath($AppRoot).TrimEnd('\')
  if ($app -ine $data -and (Test-HubOldData $app $data)) {
    $lock = New-Object System.Threading.Mutex($false, 'Local\GameHubDataMove')
    $held = $false
    try { $held = $lock.WaitOne(120000) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    try { if (Test-HubOldData $app $data) { Move-HubOldData $app $data } }
    finally { if ($held) { $lock.ReleaseMutex() } }
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $data 'data'), (Join-Path $data 'logs') | Out-Null
  return $data
}

# old data next to the scripts, not copied yet, and nothing in the data folder to overwrite
function Test-HubOldData([string]$app, [string]$data) {
  return ((Test-Path -LiteralPath (Join-Path $app 'config.json')) -and
    -not (Test-Path -LiteralPath (Join-Path $app $script:HubMovedNote)) -and
    -not (Test-Path -LiteralPath (Join-Path $data 'config.json')))
}

# Copies config.json, overrides.json, data\ and logs\ to the data folder and checks every file
# arrived (count and bytes). config.json goes last: the data folder counts as in use only once it
# is there. If anything is missing, the copied config.json is taken back so the next start tries
# again, and the program folder is left exactly as it was.
function Move-HubOldData([string]$app, [string]$data) {
  New-Item -ItemType Directory -Force -Path $data | Out-Null
  $ok = $true
  foreach ($dir in 'data', 'logs') {
    $src = Join-Path $app $dir
    if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }
    $dst = Join-Path $data $dir
    [void](& robocopy.exe $src $dst /E /COPY:DAT /DCOPY:T /R:2 /W:1 /NP /NFL /NDL /NJH /NJS)
    if ($LASTEXITCODE -ge 8) { $ok = $false; continue }
    $a = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)
    foreach ($f in $a) {
      $c = Join-Path $dst $f.FullName.Substring($src.Length).TrimStart('\')
      if (-not (Test-Path -LiteralPath $c) -or (Get-Item -LiteralPath $c -Force).Length -ne $f.Length) { $ok = $false; break }
    }
  }
  foreach ($file in 'overrides.json', 'config.json') {
    $src = Join-Path $app $file
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $data $file
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if ((Get-Item -LiteralPath $dst).Length -ne (Get-Item -LiteralPath $src).Length) { $ok = $false }
  }
  if (-not $ok) { Remove-Item -LiteralPath (Join-Path $data 'config.json') -Force -ErrorAction SilentlyContinue; return }
  $note = @(
    "Game Hub now keeps your settings and game data in:"
    "  $data"
    ""
    "They were copied there on $((Get-Date).ToString('yyyy-MM-dd HH:mm')). The old copies next to the program are no"
    "longer used: config.json, overrides.json, data\ and logs\ in this folder. Once Game Hub works as"
    "before, you can delete them. Keep this note: while it is here, they are never copied again."
  )
  [IO.File]::WriteAllText((Join-Path $app $script:HubMovedNote), (($note -join "`r`n") + "`r`n"))
}
