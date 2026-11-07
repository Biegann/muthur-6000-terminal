# Usuwa motyw MU/TH/UR 6000: profil terminala, shader i font.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'launcher\Muthur\Muthur.psm1') -Force
Uninstall-MuthurTerminal
Uninstall-MuthurClaude
Uninstall-MuthurRuntime
Write-Host 'Usunięto profil terminala, shader, font MUTHUR Mono, plugin Claude Code i nakładkę claude.'
Write-Host 'Jeśli plik fontu był używany, zniknie po ponownym uruchomieniu terminala.'
