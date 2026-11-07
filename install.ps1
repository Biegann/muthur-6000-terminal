# Instalacja motywu MU/TH/UR 6000 (etap 1: font, shader CRT, profil Windows Terminal).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$python = Join-Path $repo '.venv\Scripts\python.exe'

if (-not (Test-Path $python)) {
    Write-Host 'Tworzę środowisko Pythona (.venv)...'
    python -m venv (Join-Path $repo '.venv')
    & $python -m pip install --quiet -r (Join-Path $repo 'requirements.txt')
}

Write-Host 'Buduję font MUTHUR Mono...'
& $python (Join-Path $repo 'tools\build_font.py')
if ($LASTEXITCODE -ne 0) { throw 'Budowanie fontu nie powiodło się.' }

Write-Host 'Generuję motyw Claude Code z palety...'
& $python (Join-Path $repo 'tools\build_claude_theme.py')
if ($LASTEXITCODE -ne 0) { throw 'Generowanie motywu nie powiodło się.' }

Write-Host 'Syntezuję dźwięki...'
& $python (Join-Path $repo 'tools\build_sounds.py') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Synteza dźwięków nie powiodła się.' }

Write-Host 'Kompiluję odtwarzacz muthur-play.exe...'
& (Join-Path $repo 'tools\build_player.ps1') | Out-Null

Import-Module (Join-Path $repo 'launcher\Muthur\Muthur.psm1') -Force
$terminal = Install-MuthurTerminal
$claude = Install-MuthurClaude
$runtime = Install-MuthurRuntime
Write-Host ''
Write-Host 'ZAINSTALOWANO:' -ForegroundColor Green
$terminal | Format-List | Out-String | Write-Host
$claude | Format-List | Out-String | Write-Host
$runtime | Format-List | Out-String | Write-Host
Write-Host 'Profil „MU/TH/UR 6000” znajdziesz w menu rozwijanym Windows Terminal (strzałka obok karty).'
Write-Host 'Jeśli go tam nie ma, zamknij wszystkie okna Windows Terminal i otwórz go ponownie.'
Write-Host 'W nowej karcie wpisz: muthur on, a potem: claude'
