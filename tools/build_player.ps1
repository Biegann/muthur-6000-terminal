# Kompiluje player\MuthurPlay.cs do muthur-play.exe kompilatorem C# z .NET Framework 4.
param(
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\player')
)
$ErrorActionPreference = 'Stop'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'Brak kompilatora csc.exe z .NET Framework 4.' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'player\MuthurPlay.cs'
$exe = Join-Path $OutDir 'muthur-play.exe'
# /target:winexe: bez okna konsoli, gdy hook uruchamia odtwarzacz.
& $csc /nologo /optimize+ /target:winexe /codepage:65001 "/out:$exe" $src
if ($LASTEXITCODE -ne 0) { throw 'Kompilacja muthur-play.exe nie powiodła się.' }
$exe
