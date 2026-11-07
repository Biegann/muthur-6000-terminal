# Hook UserPromptSubmit: gdy użytkownik zwraca się do „Matki”, dodaje informację o trybie MU/TH/UR
# i odtwarza sygnał „zapytanie przyjęte” (w tle, bez czekania na koniec dźwięku).
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
Import-Module (Join-Path $PSScriptRoot 'MuthurHook.psm1')

$json = Get-MuthurPromptHookOutput -HookInputJson ([Console]::In.ReadToEnd())
if ($json) {
    $player = Join-Path $PSScriptRoot '..\player\muthur-play.exe'
    if (Test-Path -LiteralPath $player) {
        try { Start-Process -FilePath $player -ArgumentList 'inquiry' -WindowStyle Hidden } catch { }
    }
    [Console]::Out.Write($json)
}
exit 0
