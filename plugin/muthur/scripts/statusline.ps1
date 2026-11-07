# Pasek statusu Claude Code w stylu MU/TH/UR 6000.
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
Import-Module (Join-Path $PSScriptRoot 'MuthurHook.psm1')

[Console]::Out.Write((Format-MuthurStatusLine -StatusJson ([Console]::In.ReadToEnd())))
