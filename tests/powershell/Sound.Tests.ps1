# Testy dźwięków: odtwarzacz muthur-play.exe, wybór plików, przełącznik, hooki (Pester 3.4).
# Testy nie odtwarzają prawdziwego dźwięku: odtwarzacz działa w trybie --dry-run.
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'launcher\Muthur\MuthurRuntime.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $repo 'launcher\Muthur\Muthur.psm1') -Force

function Invoke-Player {
    param([string]$Exe, [string[]]$Arguments, [string]$Stdin = '')
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = ($Arguments -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.EnvironmentVariables.Remove('MUTHUR_HOME')
    $p = [Diagnostics.Process]::Start($psi)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Stdin)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd().Trim()
    $p.WaitForExit()
    @{ Out = $out; Code = $p.ExitCode }
}

Describe 'muthur-play.exe' {
    # Układ jak po instalacji: <root>\plugin\muthur\player\muthur-play.exe i ...\sounds\*.wav
    $root = Join-Path $TestDrive 'MUTHUR'
    $plugin = Join-Path $root 'plugin\muthur'
    New-Item -ItemType Directory -Force (Join-Path $plugin 'sounds'), (Join-Path $plugin 'player') | Out-Null
    foreach ($n in 'attention', 'transmission_short', 'transmission_medium', 'transmission_long') {
        'x' | Set-Content (Join-Path $plugin "sounds\$n.wav")
    }
    $exe = & (Join-Path $repo 'tools\build_player.ps1') -OutDir (Join-Path $plugin 'player')

    It 'kompiluje się do pliku exe' { Test-Path $exe | Should Be $true }
    It 'wskazuje plik dźwięku z katalogu sounds' {
        $r = Invoke-Player $exe @('attention', '--dry-run')
        $r.Code | Should Be 0
        $r.Out | Should Be (Join-Path $plugin 'sounds\attention.wav')
    }
    It 'stop: dobiera długość transmisji do długości odpowiedzi' {
        (Invoke-Player $exe @('stop', '--dry-run') '{"last_assistant_message":"ok"}').Out | Should Match 'transmission_short\.wav$'
        $mid = '{"last_assistant_message":"' + ('a' * 800) + '"}'
        (Invoke-Player $exe @('stop', '--dry-run') $mid).Out | Should Match 'transmission_medium\.wav$'
        $long = '{"last_assistant_message":"' + ('ż\"' * 1000) + '"}'
        (Invoke-Player $exe @('stop', '--dry-run') $long).Out | Should Match 'transmission_long\.wav$'
    }
    It 'ignoruje nieznane i niebezpieczne nazwy' {
        (Invoke-Player $exe @('brak', '--dry-run')).Out | Should BeNullOrEmpty
        (Invoke-Player $exe @('..\..\x', '--dry-run')).Out | Should BeNullOrEmpty
        (Invoke-Player $exe @()).Code | Should Be 0
    }
    It 'z MUTHUR_PLAY_LOG zapisuje wywołania do dziennika' {
        $log = Join-Path $TestDrive 'play.log'
        $env:MUTHUR_PLAY_LOG = $log
        try { [void](Invoke-Player $exe @('attention', '--dry-run')) }
        finally { Remove-Item Env:\MUTHUR_PLAY_LOG }
        Get-Content $log | Should Match 'attention$'
    }
    It 'milczy, gdy w state.json jest "sound": false' {
        '{ "enabled": true, "sound": false }' | Set-Content (Join-Path $root 'state.json')
        try { (Invoke-Player $exe @('attention', '--dry-run')).Out | Should Be 'WYCISZONE' }
        finally { Remove-Item (Join-Path $root 'state.json') }
    }
}

Describe 'New-MuthurSoundBank' {
    It 'przy wyłączonym dźwięku albo bez plików nic nie robi i nie zgłasza błędów' {
        $off = New-MuthurSoundBank -SoundsDir $TestDrive -Enabled $false
        { & $off 'boot' } | Should Not Throw
        $none = New-MuthurSoundBank -SoundsDir (Join-Path $TestDrive 'brak')
        { & $none 'teletype' } | Should Not Throw
    }
}

Describe 'muthur sound' {
    It 'wycisza i przywraca dźwięk, zapisując stan' {
        $root = Join-Path $TestDrive 'stan-dzwieku'
        (muthur sound off -InstallRoot $root) | Should Match 'WYCISZONY'
        (Get-MuthurState -InstallRoot $root).sound | Should Be $false
        (muthur sound on -InstallRoot $root) | Should Match 'AKTYWNY'
        (Get-MuthurState -InstallRoot $root).sound | Should Be $true
    }
}

Describe 'Hooki dźwiękowe pluginu' {
    $hooks = (Get-Content (Join-Path $repo 'plugin\muthur\hooks\hooks.json') -Raw -Encoding UTF8 | ConvertFrom-Json).hooks
    $expected = @{ Stop = 'stop'; PostToolUse = 'tool'; PostToolUseFailure = 'error'; Notification = 'attention'; StopFailure = 'alert' }
    foreach ($event in $expected.Keys) {
        It "$event odtwarza '$($expected[$event])' w tle (async)" {
            $h = $hooks.$event[0].hooks[0]
            $h.command | Should Be '${CLAUDE_PLUGIN_ROOT}/player/muthur-play.exe'
            $h.args | Should Be @($expected[$event])
            $h.async | Should Be $true
        }
    }
}

Describe 'Install-MuthurClaude z dźwiękami' {
    It 'kopiuje dźwięki i odtwarzacz do pluginu' {
        $snd = Join-Path $TestDrive 'snd'; $ply = Join-Path $TestDrive 'ply'
        New-Item -ItemType Directory $snd, $ply | Out-Null
        'x' | Set-Content (Join-Path $snd 'boot.wav')
        'x' | Set-Content (Join-Path $ply 'muthur-play.exe')
        $r = Install-MuthurClaude -LocalAppData (Join-Path $TestDrive 'lad') -SoundsDir $snd -PlayerDir $ply
        Test-Path (Join-Path $r.Plugin 'sounds\boot.wav') | Should Be $true
        Test-Path (Join-Path $r.Plugin 'player\muthur-play.exe') | Should Be $true
    }
}
