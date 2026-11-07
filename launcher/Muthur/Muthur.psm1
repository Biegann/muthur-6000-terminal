#Requires -Version 5.1
# Moduł MU/TH/UR 6000: instalacja profilu terminala, a w kolejnych etapach
# przełącznik motywu i nakładka na polecenie `claude`.

Set-StrictMode -Version Latest

$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ProfileName = 'MU/TH/UR 6000'
$script:FontFamily = 'MUTHUR Mono'

function Get-MuthurPaths {
    [CmdletBinding()]
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA
    )
    [pscustomobject]@{
        InstallRoot  = Join-Path $LocalAppData 'MUTHUR'
        FontDir      = Join-Path $LocalAppData 'Microsoft\Windows\Fonts'
        FragmentDir  = Join-Path $LocalAppData 'Microsoft\Windows Terminal\Fragments\MUTHUR'
        FontRegistry = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    }
}

function Get-MuthurPalette {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $script:RepoRoot 'config\palette.json')
    )
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function New-MuthurColorScheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Palette
    )
    $scheme = [ordered]@{
        name                = $script:ProfileName
        background          = $Palette.background
        foreground          = $Palette.phosphor
        cursorColor         = $Palette.flare   # w filmie kursor rozbłyska żółtozielono
        selectionBackground = $Palette.selection
    }
    foreach ($key in 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
        'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue',
        'brightPurple', 'brightCyan', 'brightWhite') {
        $scheme[$key] = $Palette.ansi.$key
    }
    $scheme
}

function New-MuthurTerminalFragment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShaderPath,
        [Parameter(Mandatory)]$Palette,
        [int]$FontSize = 13
    )
    # profile-init.ps1 ustawia MUTHUR_TERMINAL=1 (po tym nakładka `claude` poznaje
    # ten profil) i zielone kolory PSReadLine.
    $commandline = 'powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\MUTHUR\profile-init.ps1"'
    [ordered]@{
        profiles = @(
            [ordered]@{
                name                            = $script:ProfileName
                commandline                     = $commandline
                startingDirectory               = '%USERPROFILE%'
                tabTitle                        = $script:ProfileName
                colorScheme                     = $script:ProfileName
                font                            = [ordered]@{ face = $script:FontFamily; size = $FontSize }
                cursorShape                     = 'filledBox'
                padding                         = '28, 20'
                antialiasingMode                = 'grayscale'
                intenseTextStyle                = 'bright'
                bellStyle                       = 'none'
                useAcrylic                      = $false
                opacity                         = 100
                'experimental.pixelShaderPath'  = $ShaderPath
            }
        )
        schemes  = @(New-MuthurColorScheme -Palette $Palette)
    }
}

function Install-MuthurFont {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string[]]$FontFiles,
        [Parameter(Mandatory)][string]$FontDir,
        [Parameter(Mandatory)][string]$RegistryPath
    )
    New-Item -ItemType Directory -Force -Path $FontDir | Out-Null
    if (-not (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
    foreach ($file in $FontFiles) {
        $name = [IO.Path]::GetFileNameWithoutExtension($file)       # MUTHURMono-Bold
        $style = ($name -split '-', 2)[1]
        $label = if ($style -eq 'Regular') { "$script:FontFamily (TrueType)" } else { "$script:FontFamily $style (TrueType)" }
        $target = Join-Path $FontDir ([IO.Path]::GetFileName($file))
        if ($PSCmdlet.ShouldProcess($target, 'Instalacja fontu')) {
            $same = (Test-Path -LiteralPath $target) -and
                ((Get-FileHash -LiteralPath $file).Hash -eq (Get-FileHash -LiteralPath $target).Hash)
            if (-not $same) {
                try {
                    Copy-Item -LiteralPath $file -Destination $target -Force -ErrorAction Stop
                }
                catch [System.IO.IOException] {
                    # Zainstalowany font bywa zablokowany przez system lub terminal.
                    Write-Warning "Font $target jest używany. Nowa wersja zostanie zainstalowana po zamknięciu terminala i ponownym uruchomieniu instalacji."
                }
            }
            New-ItemProperty -Path $RegistryPath -Name $label -Value $target -PropertyType String -Force | Out-Null
        }
    }
}

function Install-MuthurTerminal {
    <#
    .SYNOPSIS
    Instaluje font MUTHUR Mono, shader CRT i profil „MU/TH/UR 6000” w Windows Terminal.
    Nie zmienia settings.json terminala: profil trafia do osobnego pliku (fragmentu).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$FontBuildDir = (Join-Path $script:RepoRoot 'build\fonts'),
        [string]$RegistryPath
    )
    $paths = Get-MuthurPaths -LocalAppData $LocalAppData
    if (-not $RegistryPath) { $RegistryPath = $paths.FontRegistry }

    $fonts = @(Get-ChildItem -LiteralPath $FontBuildDir -Filter 'MUTHURMono-*.ttf' -ErrorAction SilentlyContinue)
    if ($fonts.Count -eq 0) {
        throw "Brak zbudowanych fontów w $FontBuildDir. Uruchom najpierw tools\build_font.py."
    }

    New-Item -ItemType Directory -Force -Path $paths.InstallRoot, $paths.FragmentDir | Out-Null
    # Od Windows Terminal 1.24 fragment może używać shadera tylko z własnego
    # katalogu, podanego ścieżką względną.
    $shader = Join-Path $paths.FragmentDir 'muthur-crt.hlsl'
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'terminal\muthur-crt.hlsl') -Destination $shader -Force
    $init = Join-Path $paths.InstallRoot 'profile-init.ps1'
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'terminal\profile-init.ps1') -Destination $init -Force

    Install-MuthurFont -FontFiles $fonts.FullName -FontDir $paths.FontDir -RegistryPath $RegistryPath

    $fragment = New-MuthurTerminalFragment -ShaderPath 'muthur-crt.hlsl' -Palette (Get-MuthurPalette)
    $json = $fragment | ConvertTo-Json -Depth 6
    $fragmentFile = Join-Path $paths.FragmentDir 'muthur.json'
    [IO.File]::WriteAllText($fragmentFile, $json, (New-Object Text.UTF8Encoding($false)))

    [pscustomobject]@{
        Fragment = $fragmentFile
        Shader   = $shader
        Init     = $init
        Fonts    = @($fonts | ForEach-Object { Join-Path $paths.FontDir $_.Name })
    }
}

function Uninstall-MuthurTerminal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$RegistryPath
    )
    $paths = Get-MuthurPaths -LocalAppData $LocalAppData
    if (-not $RegistryPath) { $RegistryPath = $paths.FontRegistry }

    Remove-Item -LiteralPath $paths.FragmentDir -Recurse -Force -ErrorAction SilentlyContinue
    # muthur-crt.hlsl to pozostałość po pierwszej wersji instalatora.
    foreach ($f in 'muthur-crt.hlsl', 'profile-init.ps1') {
        Remove-Item -LiteralPath (Join-Path $paths.InstallRoot $f) -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $RegistryPath) {
        $props = (Get-ItemProperty -Path $RegistryPath).PSObject.Properties |
            Where-Object { $_.Name -like "$script:FontFamily*" }
        foreach ($p in $props) {
            Remove-ItemProperty -Path $RegistryPath -Name $p.Name -Force
            # Font może być zablokowany przez działający terminal: wtedy zostaje do restartu.
            Remove-Item -LiteralPath $p.Value -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-MuthurClaudeSettings {
    <#
    .SYNOPSIS
    Ustawienia Claude Code przekazywane flagą --settings, gdy motyw jest włączony.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginRoot
    )
    $statusScript = (Join-Path $PluginRoot 'scripts\statusline.ps1') -replace '\\', '/'
    [ordered]@{
        # Bez companyAnnouncements: Claude Code dodaje do nich prefiks „Message from …'s Organization”
        # z adresem e-mail, a gotowość interfejsu i tak ogłasza ekran rozruchowy.
        theme                = 'custom:muthur:muthur'
        spinnerVerbs         = [ordered]@{
            mode  = 'replace'
            verbs = @(
                'PRZETWARZANIE', 'OBLICZANIE', 'ANALIZA DANYCH', 'KONSULTACJA Z RDZENIEM',
                'PRZESZUKIWANIE BANKÓW PAMIĘCI', 'KORELACJA DANYCH', 'WERYFIKACJA PROTOKOŁÓW',
                'SKANOWANIE SEKTORA', 'KALIBRACJA', 'DEKODOWANIE SYGNAŁU', 'SYMULACJA',
                'OPTYMALIZACJA KURSU', 'ODCZYT TELEMETRII', 'TRANSMISJA'
            )
        }
        spinnerTipsOverride  = [ordered]@{
            label = 'MU/TH/UR'
            tips  = @(
                'Zwróć się do mnie „Matko”, aby otworzyć interfejs MU/TH/UR 6000.',
                'Rozkaz specjalny 937: dostęp wyłącznie dla oficera naukowego.',
                'Wszystkie systemy USCSS Nostromo pracują w normie.'
            )
        }
        statusLine           = [ordered]@{
            type            = 'command'
            command         = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $statusScript"
            refreshInterval = 30
        }
    }
}

function Install-MuthurClaude {
    <#
    .SYNOPSIS
    Kopiuje plugin „muthur” do %LOCALAPPDATA%\MUTHUR\plugin i zapisuje claude-settings.json.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$PluginSource = (Join-Path $script:RepoRoot 'plugin\muthur'),
        [string]$SoundsDir = (Join-Path $script:RepoRoot 'build\sounds'),
        [string]$PlayerDir = (Join-Path $script:RepoRoot 'build\player')
    )
    $paths = Get-MuthurPaths -LocalAppData $LocalAppData
    $pluginTarget = Join-Path $paths.InstallRoot 'plugin\muthur'
    if (Test-Path -LiteralPath $pluginTarget) { Remove-Item -LiteralPath $pluginTarget -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path $pluginTarget -Parent) | Out-Null
    Copy-Item -LiteralPath $PluginSource -Destination $pluginTarget -Recurse -Force
    # Typy generowane przez Claude Code przy pracy nad modem nie są potrzebne w instalacji.
    Remove-Item -LiteralPath (Join-Path $pluginTarget '.claude-plugin\types') -Recurse -Force -ErrorAction SilentlyContinue

    # Dźwięki i odtwarzacz to artefakty budowania (tools\build_sounds.py, tools\build_player.ps1).
    $wavs = @(Get-ChildItem -LiteralPath $SoundsDir -Filter '*.wav' -ErrorAction SilentlyContinue)
    if ($wavs.Count -gt 0) {
        $soundTarget = Join-Path $pluginTarget 'sounds'
        New-Item -ItemType Directory -Force -Path $soundTarget | Out-Null
        $wavs | Copy-Item -Destination $soundTarget -Force
    }
    else { Write-Warning "Brak dźwięków w $SoundsDir. Motyw zadziała bez dźwięku." }
    $player = Join-Path $PlayerDir 'muthur-play.exe'
    if (Test-Path -LiteralPath $player) {
        $playerTarget = Join-Path $pluginTarget 'player'
        New-Item -ItemType Directory -Force -Path $playerTarget | Out-Null
        Copy-Item -LiteralPath $player -Destination $playerTarget -Force
    }
    else { Write-Warning "Brak odtwarzacza $player. Hooki dźwiękowe nie zagrają." }

    $settingsFile = Join-Path $paths.InstallRoot 'claude-settings.json'
    $json = New-MuthurClaudeSettings -PluginRoot $pluginTarget | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($settingsFile, $json, (New-Object Text.UTF8Encoding($false)))

    [pscustomobject]@{ Plugin = $pluginTarget; Settings = $settingsFile }
}

function Uninstall-MuthurClaude {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$LocalAppData = $env:LOCALAPPDATA)
    $paths = Get-MuthurPaths -LocalAppData $LocalAppData
    Remove-Item -LiteralPath (Join-Path $paths.InstallRoot 'plugin') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $paths.InstallRoot 'claude-settings.json') -Force -ErrorAction SilentlyContinue
}

$script:ProfileBegin = '# >>> MU/TH/UR 6000 >>>'
$script:ProfileEnd = '# <<< MU/TH/UR 6000 <<<'

function Get-MuthurProfileBlock {
    # Tylko ASCII: blok trafia do profilu, którego kodowania nie znamy.
    @(
        $script:ProfileBegin,
        '# Motyw MU/TH/UR 6000 dla Claude Code: polecenia "muthur" i nakladka na "claude".',
        '$muthurRuntime = Join-Path $env:LOCALAPPDATA ''MUTHUR\runtime\MuthurRuntime.psm1''',
        'if (Test-Path -LiteralPath $muthurRuntime) { Import-Module $muthurRuntime -DisableNameChecking }',
        $script:ProfileEnd
    ) -join "`r`n"
}

function Read-MuthurTextFile {
    # Zwraca treść i kodowanie, tak jak czyta je Windows PowerShell 5.1:
    # z BOM -> wg BOM, bez BOM -> strona kodowa ANSI.
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = New-Object Text.UTF8Encoding($true)
        return @{ Text = $enc.GetString($bytes, 3, $bytes.Length - 3); Encoding = $enc }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return @{ Text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2); Encoding = [Text.Encoding]::Unicode }
    }
    @{ Text = [Text.Encoding]::Default.GetString($bytes); Encoding = [Text.Encoding]::Default }
}

function Remove-MuthurProfileBlockText {
    param([AllowEmptyString()][string]$Text)
    $pattern = '(?s)(\r?\n)?' + [regex]::Escape($script:ProfileBegin) + '.*?' + [regex]::Escape($script:ProfileEnd) + '(\r?\n)?'
    [regex]::Replace($Text, $pattern, "`r`n").Trim("`r", "`n")
}

function Set-MuthurProfileBlock {
    <# Dodaje (albo odświeża) blok MU/TH/UR w profilu PowerShella. Reszta pliku zostaje bez zmian. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProfilePath = $PROFILE.CurrentUserCurrentHost)
    if (Test-Path -LiteralPath $ProfilePath) {
        $file = Read-MuthurTextFile -Path $ProfilePath
    }
    else {
        New-Item -ItemType Directory -Force -Path (Split-Path $ProfilePath -Parent) | Out-Null
        $file = @{ Text = ''; Encoding = (New-Object Text.UTF8Encoding($true)) }
    }
    $body = Remove-MuthurProfileBlockText $file.Text
    $new = if ($body) { $body + "`r`n`r`n" + (Get-MuthurProfileBlock) + "`r`n" } else { (Get-MuthurProfileBlock) + "`r`n" }
    if ($PSCmdlet.ShouldProcess($ProfilePath, 'Dodanie bloku MU/TH/UR')) {
        [IO.File]::WriteAllText($ProfilePath, $new, $file.Encoding)
    }
}

function Remove-MuthurProfileBlock {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProfilePath = $PROFILE.CurrentUserCurrentHost)
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return }
    $file = Read-MuthurTextFile -Path $ProfilePath
    $body = Remove-MuthurProfileBlockText $file.Text
    $new = if ($body) { $body + "`r`n" } else { '' }
    [IO.File]::WriteAllText($ProfilePath, $new, $file.Encoding)
}

function Install-MuthurRuntime {
    <#
    .SYNOPSIS
    Instaluje polecenia `muthur` i nakładkę `claude` (moduł runtime + blok w profilu).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost
    )
    $paths = Get-MuthurPaths -LocalAppData $LocalAppData
    $runtime = Join-Path $paths.InstallRoot 'runtime'
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MuthurRuntime.psm1') -Destination $runtime -Force
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'config\palette.json') -Destination $runtime -Force
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'config\boot-timeline.json') -Destination $runtime -Force
    Set-MuthurProfileBlock -ProfilePath $ProfilePath
    [pscustomobject]@{ Runtime = $runtime; Profile = $ProfilePath }
}

function Uninstall-MuthurRuntime {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost
    )
    $paths = Get-MuthurPaths -LocalAppData $LocalAppData
    Remove-MuthurProfileBlock -ProfilePath $ProfilePath
    Remove-Item -LiteralPath (Join-Path $paths.InstallRoot 'runtime') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $paths.InstallRoot 'state.json') -Force -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Get-MuthurPaths, Get-MuthurPalette, New-MuthurColorScheme,
    New-MuthurTerminalFragment, Install-MuthurFont, Install-MuthurTerminal, Uninstall-MuthurTerminal,
    New-MuthurClaudeSettings, Install-MuthurClaude, Uninstall-MuthurClaude,
    Set-MuthurProfileBlock, Remove-MuthurProfileBlock, Install-MuthurRuntime, Uninstall-MuthurRuntime
