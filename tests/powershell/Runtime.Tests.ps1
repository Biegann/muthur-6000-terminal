# Testy nakładki `claude`, polecenia `muthur` i ekranu rozruchowego (Pester 3.4).
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'launcher\Muthur\MuthurRuntime.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $repo 'launcher\Muthur\Muthur.psm1') -Force
$palette = Get-Content (Join-Path $repo 'config\palette.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$timeline = Get-MuthurTimeline -Path (Join-Path $repo 'config\boot-timeline.json')
$esc = [char]27

function New-FakeIO {
    param([int]$KeyAfter = -1)
    # Writes: [czas animacji w ms w chwili zapisu, tekst], do sprawdzania synchronizacji.
    $log = @{ Out = New-Object Text.StringBuilder; Slept = 0; Sounds = New-Object Collections.ArrayList; Keys = 0
              Writes = New-Object Collections.ArrayList }
    $io = [pscustomobject]@{
        Write      = { param([string]$s) [void]$log.Out.Append($s); [void]$log.Writes.Add(@($log.Slept, $s)) }.GetNewClosure()
        Sleep      = { param([int]$ms) $log.Slept += $ms }.GetNewClosure()
        KeyPressed = { $log.Keys++; ($KeyAfter -ge 0) -and ($log.Keys -gt $KeyAfter) }.GetNewClosure()
        Sound      = { param([string]$cue) [void]$log.Sounds.Add($cue) }.GetNewClosure()
        Width      = 120
        Height     = 30
        Random     = New-Object Random 42
    }
    @{ IO = $io; Log = $log }
}

function ConvertTo-Plain([string]$s) {
    # Usuwa sekwencje ANSI i efekt pisania („znak, Backspace, znak”), zostawia sam tekst.
    ($s -replace "$esc\[[0-9;?]*[A-Za-z]", '') -replace '.\x08', ''
}

function New-InstallRoot {
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root 'plugin\muthur'), (Join-Path $root 'runtime') -Force | Out-Null
    Copy-Item (Join-Path $repo 'config\palette.json') (Join-Path $root 'runtime')
    Copy-Item (Join-Path $repo 'config\boot-timeline.json') (Join-Path $root 'runtime')
    $root
}

Describe 'Stan motywu' {
    It 'domyślnie wyłączony, gdy brak pliku stanu' {
        (Get-MuthurState -InstallRoot (Join-Path $TestDrive 'brak')).enabled | Should Be $false
    }
    It 'zapisuje i odczytuje stan' {
        $root = Join-Path $TestDrive 'stan'
        $s = Get-MuthurState -InstallRoot $root
        $s.enabled = $true; $s.lastFullBoot = '2026-11-07'
        Set-MuthurState -State $s -InstallRoot $root
        $r = Get-MuthurState -InstallRoot $root
        $r.enabled | Should Be $true
        $r.lastFullBoot | Should Be '2026-11-07'
    }
    It 'przeżywa uszkodzony plik stanu' {
        $root = Join-Path $TestDrive 'zly'
        New-Item -ItemType Directory $root | Out-Null
        'nie json' | Set-Content (Join-Path $root 'state.json')
        (Get-MuthurState -InstallRoot $root -WarningAction SilentlyContinue).enabled | Should Be $false
    }
}

Describe 'Get-MuthurBootMode' {
    $today = Get-Date '2026-11-07 09:00'
    It 'pełny rozruch, gdy jeszcze nie było' { Get-MuthurBootMode -State ([pscustomobject]@{ lastFullBoot = $null }) -Today $today | Should Be 'full' }
    It 'pełny rozruch następnego dnia' { Get-MuthurBootMode -State ([pscustomobject]@{ lastFullBoot = '2026-11-06' }) -Today $today | Should Be 'full' }
    It 'krótki rozruch tego samego dnia' { Get-MuthurBootMode -State ([pscustomobject]@{ lastFullBoot = '2026-11-07' }) -Today $today | Should Be 'short' }
}

Describe 'Argumenty claude' {
    It 'przepuszcza podpolecenia i flagi informacyjne' {
        foreach ($a in @(@('mcp', 'list'), @('update'), @('plugin', 'validate', '.'), @('--version'), @('-h'), @('doctor'))) {
            Test-MuthurPassthrough $a | Should Be $true
        }
    }
    It 'motywuje sesje interaktywne i zapytania' {
        foreach ($a in @(@(), @('napraw testy'), @('-p', 'hej'), @('--resume'), @('-c'), @('--model', 'opus'))) {
            Test-MuthurPassthrough $a | Should Be $false
        }
    }
    It 'rozpoznaje tryb -p / --print' {
        Test-MuthurPrintMode @('-p', 'x') | Should Be $true
        Test-MuthurPrintMode @('--print') | Should Be $true
        Test-MuthurPrintMode @('x') | Should Be $false
    }
    It 'dokleja plugin i ustawienia przed argumentami użytkownika' {
        $a = Get-MuthurClaudeArguments -InstallRoot 'C:\M' -Arguments @('-c')
        $a | Should Be @('--plugin-dir', 'C:\M\plugin\muthur', '--settings', 'C:\M\claude-settings.json', '-c')
    }
}

Describe 'Sekwencje OSC' {
    It 'ustawia 16 kolorów ANSI oraz tekst, tło i kursor' {
        $osc = Get-MuthurOscPalette -Palette $palette
        ([regex]::Matches($osc, "$esc\]4;\d+;rgb:")).Count | Should Be 16
        $osc | Should Match "$esc\]10;rgb:38/d2/96"
        $osc | Should Match "$esc\]11;rgb:08/0c/0a"
        $osc | Should Match "$esc\]12;rgb:d4/ec/66"
    }
    It 'reset przywraca paletę, tekst, tło i kursor' {
        Get-MuthurOscReset | Should Be "$esc]104$([char]7)$esc]110$([char]7)$esc]111$([char]7)$esc]112$([char]7)"
    }
}

Describe 'Invoke-MuthurWithUtf8Console' {
    It 'na czas akcji przełącza wyjście konsoli na UTF-8 i przywraca je, także po błędzie' {
        $before = [Console]::OutputEncoding.CodePage
        $script:during = $null
        Invoke-MuthurWithUtf8Console { $script:during = [Console]::OutputEncoding.CodePage }
        $script:during | Should Be 65001
        [Console]::OutputEncoding.CodePage | Should Be $before
        { Invoke-MuthurWithUtf8Console { throw 'awaria' } } | Should Throw 'awaria'
        [Console]::OutputEncoding.CodePage | Should Be $before
    }
}

Describe 'New-MuthurPacer' {
    It 'sumuje drobne pauzy według zegara zamiast spać po 15 ms każdą' {
        $sleep = New-MuthurPacer
        $sw = [Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt 100; $i++) { & $sleep 3 }
        $sw.Stop()
        # 100 × 3 ms = 300 ms. Zwykły Start-Sleep 3 dałby ok. 1500 ms.
        $sw.ElapsedMilliseconds | Should BeGreaterThan 250
        $sw.ElapsedMilliseconds | Should BeLessThan 700
    }
}

Describe 'Harmonogram rozruchu' {
    It 'animacja i generator dźwięku liczą te same etapy i czasy (PowerShell = Python)' {
        $py = Join-Path $repo '.venv\Scripts\python.exe'
        $tools = Join-Path $repo 'tools'
        foreach ($mode in 'full', 'short') {
            $ps = (Get-MuthurStagePlan -Timeline $timeline -Mode $mode | ForEach-Object { "$($_.Stage.id):$($_.Start):$($_.Ms)" }) -join ','
            # Bez cudzysłowów podwójnych w kodzie: Windows PowerShell 5.1 gubi je w argumentach programów.
            $code = "import sys; sys.path.insert(0, r'$tools'); import build_sounds as b; tl = b.load_timeline(); print(','.join(s['id'] + ':' + str(a) + ':' + str(m) for s, a, m in b.stage_plan(tl, '$mode')))"
            $pyOut = (& $py -c $code).Trim()
            $ps | Should Be $pyOut
        }
    }
    It 'etap ready trwa len(tekst) × charMs + readyHoldMs' {
        $last = @(Get-MuthurStagePlan -Timeline $timeline -Mode full)[-1]
        $last.Stage.id | Should Be 'ready'
        $last.Ms | Should Be ($timeline.texts.ready.Length * $timeline.charMs + $timeline.readyHoldMs)
    }
    It 'ośmiokąt z budzenia monitora ma nieparzystą liczbę wierszy i jest wypełniony' {
        $g = Get-MuthurOctagon -Rows 13
        $g.GetLength(0) | Should Be 13
        $g.GetLength(1) | Should Be 25
        @($g | Where-Object { $_ -ne ' ' }).Count | Should BeGreaterThan 60
    }
}

Describe 'Invoke-MuthurBoot' {
    $plan = @(Get-MuthurStagePlan -Timeline $timeline -Mode full)
    $total = ($plan | Measure-Object -Property Ms -Sum).Sum
    $readyStart = $plan[-1].Start

    It 'pełny rozruch: polskie teksty z filmowej sekwencji i jedna ścieżka dźwiękowa' {
        $f = New-FakeIO
        Invoke-MuthurBoot -Mode full -IO $f.IO -Palette $palette -Timeline $timeline | Should Be 'completed'
        $plain = ConvertTo-Plain $f.Log.Out.ToString()
        foreach ($t in 'USCSS NOSTROMO 180924609', 'AUTORYZACJA DOSTĘPU', 'PRZYJĘTA', 'PODTRZYMANIE ŻYCIA',
            'SYGNAŁ NIEZNANEGO POCHODZENIA', 'WYKRYTY', 'MU/TH/UR 6000', 'MACIERZ ADRESOWA NADZORU',
            'DOWODZENIE', 'INTERFEJS', 'GOTOWY DO ZAPYTAŃ') {
            $plain | Should Match ([regex]::Escape($t))
        }
        @($f.Log.Sounds) | Should Be @('boot_full')
    }
    It 'trwa dokładnie tyle, ile ścieżka dźwiękowa (suma etapów harmonogramu)' {
        $f = New-FakeIO
        [void](Invoke-MuthurBoot -Mode full -IO $f.IO -Palette $palette -Timeline $timeline)
        $f.Log.Slept | Should Be $total
        $total | Should BeGreaterThan 8000
        $total | Should BeLessThan 9000
    }
    It 'każda litera gotowości pojawia się w chwili swojego stuku w ścieżce dźwiękowej' {
        $f = New-FakeIO
        [void](Invoke-MuthurBoot -Mode full -IO $f.IO -Palette $palette -Timeline $timeline)
        $flare = "$esc[38;2;212;236;102m"
        $text = $timeline.texts.ready
        foreach ($i in 0, 5, 14, ($text.Length - 1)) {
            $expected = $readyStart + $i * $timeline.charMs
            $hit = @($f.Log.Writes | Where-Object { $_[0] -eq $expected -and $_[1].Contains("$flare$esc[4m") -and $_[1].Contains($flare + "$esc[4m" + $esc + '[58;2;244;255;246m' + $text[$i]) })
            $hit.Count | Should Be 1
        }
    }
    It 'tabela adresowa pojawia się dokładnie po fazie skanowania' {
        $f = New-FakeIO
        [void](Invoke-MuthurBoot -Mode full -IO $f.IO -Palette $palette -Timeline $timeline)
        $m = $plan | Where-Object { $_.Stage.id -eq 'matrix' }
        $title = @($f.Log.Writes | Where-Object { $_[1].Contains('MACIERZ ADRESOWA NADZORU') })
        $title[0][0] | Should Be ($m.Start + $m.Stage.scanMs)
    }
    It 'krótki rozruch: pełne lampki i schemat, potem gotowość; ścieżka boot_short, ok. 4 s' {
        $f = New-FakeIO
        Invoke-MuthurBoot -Mode short -IO $f.IO -Palette $palette -Timeline $timeline | Should Be 'completed'
        @($f.Log.Sounds) | Should Be @('boot_short')
        @(Get-MuthurStagePlan -Timeline $timeline -Mode short | ForEach-Object { $_.Stage.id }) | Should Be @('room', 'crt', 'clear', 'ready')
        $short = (Get-MuthurStagePlan -Timeline $timeline -Mode short | Measure-Object -Property Ms -Sum).Sum
        $f.Log.Slept | Should Be $short
        $short | Should BeGreaterThan 3500
        $short | Should BeLessThan 4500
        ConvertTo-Plain $f.Log.Out.ToString() | Should Match 'MU/TH/UR 6000'
    }
    It 'dowolny klawisz pomija animację, ucina dźwięk i pokazuje gotowość interfejsu' {
        $f = New-FakeIO -KeyAfter 5
        Invoke-MuthurBoot -Mode full -IO $f.IO -Palette $palette -Timeline $timeline | Should Be 'skipped'
        $out = $f.Log.Out.ToString()
        ConvertTo-Plain $out | Should Match 'INTERFEJS 2037 GOTOWY DO ZAPYTAŃ'
        $f.Log.Sounds[-1] | Should Be 'silence-all'
        $out.EndsWith("$esc[0m$esc[?25h`r`n`r`n") | Should Be $true
    }
}

Describe 'Invoke-MuthurClaude' {
    $runner = {
        param($exe, $argv)
        $script:ran = @{ Exe = $exe; Args = @($argv) }
    }
    $today = Get-Date '2026-11-07 10:00'
    $savedWt = $env:WT_SESSION; $savedMt = $env:MUTHUR_TERMINAL; $savedDis = $env:MUTHUR_DISABLE

    It 'przy wyłączonym motywie uruchamia claude bez zmian' {
        $root = New-InstallRoot
        $script:ran = $null
        Invoke-MuthurClaude -Arguments @('-c') -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -Interactive:$false
        $script:ran.Args | Should Be @('-c')
    }
    It 'przy włączonym motywie: rozruch pełny, zapis daty, plugin w argumentach' {
        $root = New-InstallRoot
        Set-MuthurState -InstallRoot $root -State ([pscustomobject]@{ enabled = $true; lastFullBoot = $null; recolorOtherTerminals = $false; sound = $true })
        $f = New-FakeIO
        $script:ran = $null
        Invoke-MuthurClaude -Arguments @() -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -IO $f.IO -Interactive -Today $today
        $script:ran.Args[0] | Should Be '--plugin-dir'
        ConvertTo-Plain $f.Log.Out.ToString() | Should Match 'MACIERZ ADRESOWA NADZORU'
        (Get-MuthurState -InstallRoot $root).lastFullBoot | Should Be '2026-11-07'

        $f2 = New-FakeIO
        Invoke-MuthurClaude -Arguments @() -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -IO $f2.IO -Interactive -Today $today
        $plain2 = ConvertTo-Plain $f2.Log.Out.ToString()
        $plain2 | Should Not Match 'MACIERZ'
        $plain2 | Should Match 'GOTOWY DO ZAPYTAŃ'
    }
    It 'w trybie -p dokleja plugin, ale nie odtwarza rozruchu' {
        $root = New-InstallRoot
        Set-MuthurState -InstallRoot $root -State ([pscustomobject]@{ enabled = $true; lastFullBoot = $null; recolorOtherTerminals = $false; sound = $true })
        $f = New-FakeIO
        Invoke-MuthurClaude -Arguments @('-p', 'Matko?') -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -IO $f.IO -Interactive
        $script:ran.Args[-2..-1] | Should Be @('-p', 'Matko?')
        $script:ran.Args[0] | Should Be '--plugin-dir'
        $f.Log.Out.Length | Should Be 0
    }
    It 'podpolecenia przechodzą bez motywu' {
        $root = New-InstallRoot
        Set-MuthurState -InstallRoot $root -State ([pscustomobject]@{ enabled = $true; lastFullBoot = $null; recolorOtherTerminals = $false; sound = $true })
        Invoke-MuthurClaude -Arguments @('mcp', 'list') -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -Interactive:$false
        $script:ran.Args | Should Be @('mcp', 'list')
    }
    It 'MUTHUR_DISABLE=1 wyłącza motyw jednorazowo' {
        $root = New-InstallRoot
        Set-MuthurState -InstallRoot $root -State ([pscustomobject]@{ enabled = $true; lastFullBoot = $null; recolorOtherTerminals = $false; sound = $true })
        $env:MUTHUR_DISABLE = '1'
        try { Invoke-MuthurClaude -Arguments @('x') -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -Interactive:$false }
        finally { $env:MUTHUR_DISABLE = $savedDis }
        $script:ran.Args | Should Be @('x')
    }
    It 'poza profilem MU/TH/UR przekolorowuje terminal i przywraca kolory nawet po błędzie' {
        $root = New-InstallRoot
        Set-MuthurState -InstallRoot $root -State ([pscustomobject]@{ enabled = $true; lastFullBoot = '2026-11-07'; recolorOtherTerminals = $true; sound = $true })
        $env:WT_SESSION = 'test'; $env:MUTHUR_TERMINAL = $null
        $f = New-FakeIO
        try {
            { Invoke-MuthurClaude -Arguments @() -InstallRoot $root -ClaudeExe 'claude.exe' -Runner { throw 'awaria' } -IO $f.IO -Interactive -Today $today } | Should Throw 'awaria'
        }
        finally { $env:WT_SESSION = $savedWt; $env:MUTHUR_TERMINAL = $savedMt }
        $out = $f.Log.Out.ToString()
        $out | Should Match "$esc\]4;0;rgb:"
        $out.EndsWith((Get-MuthurOscReset)) | Should Be $true
    }
    It 'w profilu MU/TH/UR nie przekolorowuje terminala' {
        $root = New-InstallRoot
        Set-MuthurState -InstallRoot $root -State ([pscustomobject]@{ enabled = $true; lastFullBoot = '2026-11-07'; recolorOtherTerminals = $true; sound = $true })
        $env:WT_SESSION = 'test'; $env:MUTHUR_TERMINAL = '1'
        $f = New-FakeIO
        try { Invoke-MuthurClaude -Arguments @() -InstallRoot $root -ClaudeExe 'claude.exe' -Runner $runner -IO $f.IO -Interactive -Today $today }
        finally { $env:WT_SESSION = $savedWt; $env:MUTHUR_TERMINAL = $savedMt }
        $f.Log.Out.ToString() | Should Not Match "$esc\]4;"
    }
}

Describe 'Polecenie muthur' {
    It 'on / off / status' {
        $root = New-InstallRoot
        (muthur on -InstallRoot $root) | Should Match 'MOTYW AKTYWNY'
        (Get-MuthurState -InstallRoot $root).enabled | Should Be $true
        ((muthur status -InstallRoot $root) -join "`n") | Should Match 'MOTYW \.+ AKTYWNY'
        (muthur off -InstallRoot $root) | Should Match 'MOTYW WYŁĄCZONY'
        (Get-MuthurState -InstallRoot $root).enabled | Should Be $false
    }
    It 'funkcja claude przykrywa claude.exe w PowerShellu' {
        (Get-Command claude).CommandType | Should Be 'Function'
    }
}

Describe 'Blok w profilu PowerShella' {
    It 'dodaje blok raz, zachowuje istniejącą treść i kodowanie ANSI' {
        $p = Join-Path $TestDrive 'profile1.ps1'
        [IO.File]::WriteAllText($p, "Set-Alias ll Get-ChildItem # zażółć`r`n", [Text.Encoding]::Default)
        Set-MuthurProfileBlock -ProfilePath $p
        Set-MuthurProfileBlock -ProfilePath $p
        $text = [IO.File]::ReadAllText($p, [Text.Encoding]::Default)
        ([regex]::Matches($text, '>>> MU/TH/UR 6000 >>>')).Count | Should Be 1
        $text | Should Match 'zażółć'
        $text | Should Match 'MuthurRuntime\.psm1'
    }
    It 'usunięcie bloku przywraca pierwotną treść' {
        $p = Join-Path $TestDrive 'profile2.ps1'
        $orig = "`$x = 1`r`n"
        [IO.File]::WriteAllText($p, $orig, (New-Object Text.UTF8Encoding($true)))
        Set-MuthurProfileBlock -ProfilePath $p
        Remove-MuthurProfileBlock -ProfilePath $p
        [IO.File]::ReadAllText($p) | Should Be $orig
        $bytes = [IO.File]::ReadAllBytes($p)
        $bytes[0] | Should Be 0xEF
    }
    It 'tworzy profil, gdy go nie ma, a załadowany blok importuje moduł' {
        $p = Join-Path $TestDrive 'nowy\Microsoft.PowerShell_profile.ps1'
        Set-MuthurProfileBlock -ProfilePath $p
        Test-Path $p | Should Be $true
        { [scriptblock]::Create([IO.File]::ReadAllText($p)) } | Should Not Throw
    }
}
