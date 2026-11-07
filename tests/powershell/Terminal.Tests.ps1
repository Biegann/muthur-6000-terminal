# Testy Pester 3.4 (wbudowany w Windows PowerShell 5.1).
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'launcher\Muthur\Muthur.psm1') -Force

Describe 'Get-MuthurPalette' {
    It 'wczytuje paletę z pełnym zestawem 16 kolorów ANSI' {
        $p = Get-MuthurPalette
        $p.background | Should Match '^#[0-9A-F]{6}$'
        @($p.ansi.PSObject.Properties).Count | Should Be 16
    }
}

Describe 'New-MuthurColorScheme' {
    It 'mapuje paletę na schemat Windows Terminal' {
        $s = New-MuthurColorScheme -Palette (Get-MuthurPalette)
        $s.name | Should Be 'MU/TH/UR 6000'
        # Kolory z klatek filmu: tekst #38D296 (miętowy), kursor jak rozbłysk znaku.
        $s.foreground | Should Be '#38D296'
        $s.cursorColor | Should Be '#D4EC66'
        $s.brightWhite | Should Be '#F4FFF6'
        @($s.Keys).Count | Should Be 21
    }
}

Describe 'New-MuthurTerminalFragment' {
    $fragment = New-MuthurTerminalFragment -ShaderPath 'C:\x\muthur-crt.hlsl' -Palette (Get-MuthurPalette)
    $json = $fragment | ConvertTo-Json -Depth 6
    $parsed = $json | ConvertFrom-Json

    It 'tworzy jeden profil i jeden schemat' {
        @($parsed.profiles).Count | Should Be 1
        @($parsed.schemes).Count | Should Be 1
    }
    It 'ustawia font, schemat kolorów i shader' {
        $p = $parsed.profiles[0]
        $p.font.face | Should Be 'MUTHUR Mono'
        $p.colorScheme | Should Be $parsed.schemes[0].name
        $p.'experimental.pixelShaderPath' | Should Be 'C:\x\muthur-crt.hlsl'
    }
    It 'uruchamia skrypt startowy profilu w katalogu domowym' {
        $parsed.profiles[0].commandline | Should Match '-File "%LOCALAPPDATA%\\MUTHUR\\profile-init\.ps1"'
        $parsed.profiles[0].startingDirectory | Should Be '%USERPROFILE%'
    }
}

Describe 'profile-init.ps1' {
    It 'ustawia MUTHUR_TERMINAL i nie zgłasza błędów' {
        $script = Join-Path $repo 'terminal\profile-init.ps1'
        $out = powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$script'; `$env:MUTHUR_TERMINAL" 2>&1
        $LASTEXITCODE | Should Be 0
        ($out | Select-Object -Last 1) | Should Be '1'
    }
}

Describe 'Install-MuthurFont' {
    $reg = 'HKCU:\Software\MuthurPesterTest\Fonts'
    $src = Join-Path $TestDrive 'src'
    $dst = Join-Path $TestDrive 'dst'
    New-Item -ItemType Directory -Path $src, $dst | Out-Null
    $font = Join-Path $src 'MUTHURMono-Regular.ttf'
    $target = Join-Path $dst 'MUTHURMono-Regular.ttf'
    'v2' | Set-Content $font

    try {
        It 'nie przerywa instalacji, gdy zainstalowany font jest zablokowany' {
            'v1' | Set-Content $target
            $lock = [IO.File]::Open($target, 'Open', 'Read', 'Read')
            try {
                { Install-MuthurFont -FontFiles $font -FontDir $dst -RegistryPath $reg -WarningAction SilentlyContinue } | Should Not Throw
            }
            finally { $lock.Close() }
            (Get-ItemProperty $reg).'MUTHUR Mono (TrueType)' | Should Be $target
        }
        It 'pomija kopiowanie identycznego fontu (nawet zablokowanego)' {
            Copy-Item $font $target -Force
            $lock = [IO.File]::Open($target, 'Open', 'Read', 'Read')
            try {
                Install-MuthurFont -FontFiles $font -FontDir $dst -RegistryPath $reg -WarningVariable warn -WarningAction SilentlyContinue
                @($warn).Count | Should Be 0
            }
            finally { $lock.Close() }
        }
    }
    finally {
        Remove-Item 'HKCU:\Software\MuthurPesterTest' -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Install-MuthurTerminal / Uninstall-MuthurTerminal' {
    $reg = 'HKCU:\Software\MuthurPesterTest\Fonts'
    $fontBuild = Join-Path $TestDrive 'fonts'
    New-Item -ItemType Directory -Path $fontBuild | Out-Null
    'regular' | Set-Content (Join-Path $fontBuild 'MUTHURMono-Regular.ttf')
    'bold' | Set-Content (Join-Path $fontBuild 'MUTHURMono-Bold.ttf')
    $lad = Join-Path $TestDrive 'LocalAppData'

    try {
        $result = Install-MuthurTerminal -LocalAppData $lad -FontBuildDir $fontBuild -RegistryPath $reg

        It 'zapisuje fragment terminala jako poprawny JSON bez BOM' {
            Test-Path $result.Fragment | Should Be $true
            $bytes = [IO.File]::ReadAllBytes($result.Fragment)
            $bytes[0] | Should Be ([byte][char]'{')
            $parsed = Get-Content $result.Fragment -Raw | ConvertFrom-Json
            $parsed.profiles[0].'experimental.pixelShaderPath' | Should Be 'muthur-crt.hlsl'
        }
        It 'kładzie shader obok fragmentu (wymóg Windows Terminal 1.24)' {
            Test-Path $result.Shader | Should Be $true
            Split-Path $result.Shader -Parent | Should Be (Split-Path $result.Fragment -Parent)
        }
        It 'kopiuje skrypt startowy profilu' {
            $result.Init | Should Be (Join-Path $lad 'MUTHUR\profile-init.ps1')
            Test-Path $result.Init | Should Be $true
        }
        It 'instaluje oba fonty dla bieżącego użytkownika' {
            (Get-ItemProperty $reg).'MUTHUR Mono (TrueType)' | Should Be (Join-Path $lad 'Microsoft\Windows\Fonts\MUTHURMono-Regular.ttf')
            (Get-ItemProperty $reg).'MUTHUR Mono Bold (TrueType)' | Should Not BeNullOrEmpty
            $result.Fonts | ForEach-Object { Test-Path $_ | Should Be $true }
        }

        Uninstall-MuthurTerminal -LocalAppData $lad -RegistryPath $reg

        It 'odinstalowanie usuwa fragment, shader, fonty i wpisy rejestru' {
            Test-Path $result.Fragment | Should Be $false
            Test-Path $result.Shader | Should Be $false
            Test-Path $result.Init | Should Be $false
            $result.Fonts | ForEach-Object { Test-Path $_ | Should Be $false }
            @((Get-ItemProperty $reg).PSObject.Properties | Where-Object { $_.Name -like 'MUTHUR Mono*' }).Count | Should Be 0
        }
    }
    finally {
        Remove-Item 'HKCU:\Software\MuthurPesterTest' -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'zgłasza błąd, gdy fonty nie są zbudowane' {
        { Install-MuthurTerminal -LocalAppData $lad -FontBuildDir (Join-Path $TestDrive 'brak') -RegistryPath $reg } |
            Should Throw 'Brak zbudowanych fontów'
    }
    Remove-Item 'HKCU:\Software\MuthurPesterTest' -Recurse -Force -ErrorAction SilentlyContinue
}
