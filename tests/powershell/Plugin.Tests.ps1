# Testy pluginu Claude Code (Pester 3.4).
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$scripts = Join-Path $repo 'plugin\muthur\scripts'
Import-Module (Join-Path $scripts 'MuthurHook.psm1') -Force
Import-Module (Join-Path $repo 'launcher\Muthur\Muthur.psm1') -Force

Describe 'Test-MuthurAddress' {
    $positive = @(
        'Matko, jaki jest status statku?',
        'matko sprawdź testy',
        'Powiedz mi, Matko, co dalej.',
        'Mother, what is special order 937?',
        'MU/TH/UR: przeanalizuj log',
        'Hej, Matka! Pomóż.',
        'Matka?',
        'mu-th-ur, raport',
        'Dobra Mother, startujemy'
    )
    $negative = @(
        '',
        'Wymień płytę matka w komputerze',
        'class Mother extends Base {}',
        'Uruchom muthur on i sprawdź profil',
        'Matkowanie projektom nie jest moją rolą',
        'Moja matka dzwoniła',
        'Napraw plik MuthurHook.psm1'
    )
    foreach ($p in $positive) {
        It "wykrywa zwrot: '$p'" { Test-MuthurAddress -Prompt $p | Should Be $true }
    }
    foreach ($n in $negative) {
        It "ignoruje: '$n'" { Test-MuthurAddress -Prompt $n | Should Be $false }
    }
}

Describe 'Get-MuthurPromptHookOutput' {
    It 'zwraca additionalContext dla zwrotu do Matki' {
        $in = @{ prompt = 'Matko, raport' } | ConvertTo-Json
        $out = Get-MuthurPromptHookOutput -HookInputJson $in | ConvertFrom-Json
        $out.hookSpecificOutput.hookEventName | Should Be 'UserPromptSubmit'
        $out.hookSpecificOutput.additionalContext | Should Match 'Tryb MU/TH/UR'
    }
    It 'nic nie zwraca dla zwykłej wiadomości' {
        Get-MuthurPromptHookOutput -HookInputJson (@{ prompt = 'napraw testy' } | ConvertTo-Json) | Should BeNullOrEmpty
    }
    It 'nie wywraca się na niepoprawnym JSON' {
        Get-MuthurPromptHookOutput -HookInputJson 'to nie json' | Should BeNullOrEmpty
    }
}

Describe 'prompt-submit.ps1 (pełny proces, UTF-8 na stdin)' {
    It 'czyta polskie znaki z UTF-8 i wypisuje poprawny JSON' {
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
        $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scripts\prompt-submit.ps1`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $proc = [Diagnostics.Process]::Start($psi)
        $bytes = [Text.Encoding]::UTF8.GetBytes('{"prompt":"Dobrze, Matko — sprawdź źródła"}')
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        $proc.ExitCode | Should Be 0
        ($stdout | ConvertFrom-Json).hookSpecificOutput.additionalContext | Should Match 'MATKI'
    }
}

Describe 'Format-MuthurStatusLine' {
    $now = Get-Date '2026-11-07 14:05'
    $json = @{
        model          = @{ display_name = 'Opus' }
        workspace      = @{ current_dir = 'D:\projekty\theme' }
        context_window = @{ used_percentage = 42.7 }
    } | ConvertTo-Json
    $line = Format-MuthurStatusLine -StatusJson $json -Now $now
    $plain = $line -replace "$([char]27)\[[0-9;]*m", ''

    It 'zawiera nazwę systemu, model, katalog, pamięć i datę z 2122 roku (krótko, bez numeru statku)' {
        $plain | Should Be '▮ MU/TH/UR 6000 │ OPUS │ THEME │ PAMIĘĆ 42% │ 07.11.2122 14:05'
    }
    It 'koloruje wysokie zużycie pamięci na czerwono' {
        $hot = @{ context_window = @{ used_percentage = 95 } } | ConvertTo-Json
        Format-MuthurStatusLine -StatusJson $hot -Now $now | Should Match "$([char]27)\[31mPAMIĘĆ 95%"
    }
    It 'działa przy pustych danych' {
        $p = (Format-MuthurStatusLine -StatusJson '' -Now $now) -replace "$([char]27)\[[0-9;]*m", ''
        $p | Should Be '▮ MU/TH/UR 6000 │ 07.11.2122 14:05'
    }
}

Describe 'New-MuthurClaudeSettings / Install-MuthurClaude' {
    $lad = Join-Path $TestDrive 'LocalAppData'
    $result = Install-MuthurClaude -LocalAppData $lad
    $settings = Get-Content $result.Settings -Raw -Encoding UTF8 | ConvertFrom-Json

    It 'kopiuje plugin z manifestem, motywem, stylem i hookami' {
        foreach ($f in '.claude-plugin\plugin.json', 'themes\muthur.json', 'output-styles\matka.md', 'hooks\hooks.json', 'scripts\statusline.ps1') {
            Test-Path (Join-Path $result.Plugin $f) | Should Be $true
        }
    }
    It 'wybiera motyw z pluginu i polskie czasowniki spinnera' {
        $settings.theme | Should Be 'custom:muthur:muthur'
        $settings.spinnerVerbs.mode | Should Be 'replace'
        $settings.spinnerVerbs.verbs -contains 'PRZESZUKIWANIE BANKÓW PAMIĘCI' | Should Be $true
    }
    It 'nie używa companyAnnouncements (prefiks z adresem e-mail psuje klimat)' {
        $settings.PSObject.Properties['companyAnnouncements'] | Should BeNullOrEmpty
    }
    It 'wskazuje skrypt paska statusu ścieżką z ukośnikami' {
        $settings.statusLine.command | Should Match ([regex]::Escape(((Join-Path $result.Plugin 'scripts\statusline.ps1') -replace '\\', '/')))
        $settings.statusLine.command | Should Not Match '\\'
    }
    It 'odinstalowanie usuwa plugin i ustawienia' {
        Uninstall-MuthurClaude -LocalAppData $lad
        Test-Path $result.Plugin | Should Be $false
        Test-Path $result.Settings | Should Be $false
    }
}
