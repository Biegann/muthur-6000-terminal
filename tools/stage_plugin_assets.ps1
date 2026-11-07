# Kopiuje zbudowane dźwięki i odtwarzacz do plugin\muthur, żeby plugin działał także
# po instalacji z marketplace'u (/plugin install), bez install.ps1.
# Uruchom po tools\build_sounds.py i tools\build_player.ps1, przed commitem wydania.
param(
    [string]$Repo = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
$plugin = Join-Path $Repo 'plugin\muthur'
$wavs = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'build\sounds') -Filter '*.wav')
if ($wavs.Count -eq 0) { throw 'Brak dźwięków w build\sounds: uruchom tools\build_sounds.py.' }
$player = Join-Path $Repo 'build\player\muthur-play.exe'
if (-not (Test-Path -LiteralPath $player)) { throw 'Brak build\player\muthur-play.exe: uruchom tools\build_player.ps1.' }

$sounds = Join-Path $plugin 'sounds'
if (Test-Path -LiteralPath $sounds) { Remove-Item -LiteralPath $sounds -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sounds | Out-Null
$wavs | Copy-Item -Destination $sounds -Force
New-Item -ItemType Directory -Force -Path (Join-Path $plugin 'player') | Out-Null
Copy-Item -LiteralPath $player -Destination (Join-Path $plugin 'player') -Force
"Skopiowano $($wavs.Count) dźwięków i muthur-play.exe do $plugin"
