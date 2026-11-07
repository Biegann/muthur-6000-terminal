#Requires -Version 5.1
# MU/TH/UR 6000: moduł ładowany z profilu PowerShella.
# Polecenie `muthur` (on/off/status/boot) i nakładka na `claude` z ekranem rozruchowym.

Set-StrictMode -Version Latest

$script:Esc = [char]27
$script:DefaultInstallRoot = if ($env:MUTHUR_HOME) { $env:MUTHUR_HOME } else { Split-Path $PSScriptRoot -Parent }

# Podpolecenia i flagi claude, które przepuszczamy bez motywu (nie przyjmują --plugin-dir).
$script:PassthroughCommands = @(
    'agents', 'attach', 'auth', 'auto-mode', 'doctor', 'gateway', 'import', 'install', 'logs',
    'mcp', 'plugin', 'plugins', 'purge', 'respawn', 'rm', 'setup-token', 'stop', 'kill',
    'ultrareview', 'update', 'upgrade'
)
$script:PassthroughFlags = @('-v', '--version', '-h', '--help')
$script:PrintFlags = @('-p', '--print')

# ─── Stan ────────────────────────────────────────────────────────────────────

function Get-MuthurState {
    [CmdletBinding()]
    param([string]$InstallRoot = $script:DefaultInstallRoot)
    $state = [ordered]@{ enabled = $false; lastFullBoot = $null; recolorOtherTerminals = $true; sound = $true }
    $file = Join-Path $InstallRoot 'state.json'
    if (Test-Path -LiteralPath $file) {
        try {
            $saved = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $saved.PSObject.Properties) { $state[$p.Name] = $p.Value }
        }
        catch { Write-Warning "MU/TH/UR: uszkodzony plik stanu $file, używam ustawień domyślnych." }
    }
    [pscustomobject]$state
}

function Set-MuthurState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [string]$InstallRoot = $script:DefaultInstallRoot
    )
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    $json = $State | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'state.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-MuthurBootMode {
    <# Pełny rozruch raz dziennie, potem krótki. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [datetime]$Today = (Get-Date)
    )
    if ($State.lastFullBoot -eq $Today.ToString('yyyy-MM-dd')) { 'short' } else { 'full' }
}

# ─── Argumenty claude ────────────────────────────────────────────────────────

function Test-MuthurPassthrough {
    <# True, gdy wywołanie claude ma pominąć motyw (podpolecenia, --version, --help). #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Arguments = @())
    if ($Arguments.Count -eq 0) { return $false }
    foreach ($a in $Arguments) {
        if ($script:PassthroughFlags -contains [string]$a) { return $true }
    }
    $first = [string]$Arguments[0]
    return $script:PassthroughCommands -contains $first
}

function Test-MuthurPrintMode {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Arguments = @())
    foreach ($a in $Arguments) { if ($script:PrintFlags -contains [string]$a) { return $true } }
    $false
}

function Get-MuthurClaudeArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [AllowEmptyCollection()][object[]]$Arguments = @()
    )
    @('--plugin-dir', (Join-Path $InstallRoot 'plugin\muthur'),
      '--settings', (Join-Path $InstallRoot 'claude-settings.json')) + @($Arguments)
}

function Get-MuthurClaudeExe {
    $cmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { throw 'MU/TH/UR: nie znaleziono programu claude w PATH.' }
    $cmd.Source
}

# ─── Kolory ──────────────────────────────────────────────────────────────────

function Get-MuthurPaletteRuntime {
    [CmdletBinding()]
    param([string]$InstallRoot = $script:DefaultInstallRoot)
    Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime\palette.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-MuthurAnsi {
    <# '#8AF5A0' -> sekwencja koloru tekstu 24-bit. #>
    param([Parameter(Mandatory)][string]$Hex)
    $r = [Convert]::ToInt32($Hex.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(5, 2), 16)
    "$script:Esc[38;2;$r;$g;${b}m"
}

function Get-MuthurOscPalette {
    <# Sekwencje OSC 4/10/11/12 przekolorowujące terminal na paletę MU/TH/UR. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Palette)
    $e = $script:Esc
    $bel = [char]7
    function Osc([string]$hex) {
        $h = $hex.TrimStart('#').ToLowerInvariant()
        "rgb:$($h.Substring(0,2))/$($h.Substring(2,2))/$($h.Substring(4,2))"
    }
    $order = 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
        'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt 16; $i++) {
        [void]$sb.Append("$e]4;$i;$(Osc $Palette.ansi.($order[$i]))$bel")
    }
    [void]$sb.Append("$e]10;$(Osc $Palette.phosphor)$bel")
    [void]$sb.Append("$e]11;$(Osc $Palette.background)$bel")
    [void]$sb.Append("$e]12;$(Osc $Palette.flare)$bel")
    $sb.ToString()
}

function Get-MuthurOscReset {
    $e = $script:Esc; $bel = [char]7
    "$e]104$bel$e]110$bel$e]111$bel$e]112$bel"
}

function Test-MuthurCanRecolor {
    # Terminale obsługujące OSC 4/10/11: Windows Terminal i terminale z TERM_PROGRAM (VS Code itp.).
    [bool]($env:WT_SESSION -or $env:TERM_PROGRAM)
}

function Enable-MuthurVirtualTerminal {
    # Włącza interpretację sekwencji ANSI w konsoli (ENABLE_VIRTUAL_TERMINAL_PROCESSING).
    if (-not ('Muthur.ConsoleMode' -as [type])) {
        Add-Type -Namespace Muthur -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr h, uint mode);
'@
    }
    $h = [Muthur.ConsoleMode]::GetStdHandle(-11)
    $mode = 0
    if ([Muthur.ConsoleMode]::GetConsoleMode($h, [ref]$mode)) {
        [void][Muthur.ConsoleMode]::SetConsoleMode($h, $mode -bor 0x0004)
    }
}

function Invoke-MuthurWithUtf8Console {
    <#
    Windows PowerShell 5.1 pisze do konsoli w stronie kodowej OEM (np. CP852), w której
    nie ma znaków ▮ · ■. Na czas akcji przełącza wyjście na UTF-8 i zawsze przywraca poprzednie.
    #>
    param([Parameter(Mandatory)][scriptblock]$Action)
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        & $Action
    }
    finally {
        [Console]::OutputEncoding = $previous
    }
}

# ─── Ekran rozruchowy ────────────────────────────────────────────────────────
#
# Animacja i ścieżka dźwiękowa korzystają z jednego harmonogramu
# (config/boot-timeline.json, w instalacji: runtime\boot-timeline.json).
# Dźwięk to jeden plik WAV na cały rozruch (boot_full.wav / boot_short.wav),
# wygenerowany z tego samego harmonogramu. Animacja wyświetla każde zdarzenie
# w chwili bezwzględnej od startu dźwięku, więc obraz i dźwięk się nie rozjeżdżają.

function New-MuthurPacer {
    <#
    Pauzy liczone według zegara. Start-Sleep ma rozdzielczość ok. 15 ms, więc setki pauz
    po kilka ms trwałyby dłużej, niż powinny. Pacer sumuje żądany czas i śpi dopiero wtedy,
    gdy animacja wyprzedza harmonogram o co najmniej 10 ms. Wywołanie z -1 zeruje zegar
    (tuż po starcie dźwięku).
    #>
    $clock = @{ Watch = [Diagnostics.Stopwatch]::StartNew(); Target = 0.0 }
    {
        param([int]$ms)
        if ($ms -lt 0) { $clock.Watch.Restart(); $clock.Target = 0.0; return }
        $clock.Target += $ms
        $ahead = [int]($clock.Target - $clock.Watch.ElapsedMilliseconds)
        if ($ahead -ge 10) { Start-Sleep -Milliseconds $ahead }
    }.GetNewClosure()
}

function New-MuthurSoundBank {
    <#
    Ścieżki rozruchu odtwarzane przez SoundPlayer (wczytane z góry, więc startują od razu).
    Sygnały: 'boot_full' / 'boot_short' (start), 'silence-all' (pominięcie klawiszem).
    #>
    param(
        [Parameter(Mandatory)][string]$SoundsDir,
        [bool]$Enabled = $true
    )
    if (-not $Enabled -or -not (Test-Path -LiteralPath $SoundsDir)) { return { param([string]$cue) } }
    $players = @{}
    foreach ($name in 'boot_full', 'boot_short') {
        $path = Join-Path $SoundsDir "$name.wav"
        if (Test-Path -LiteralPath $path) {
            try { $p = New-Object Media.SoundPlayer $path; $p.Load(); $players[$name] = $p } catch { }
        }
    }
    {
        param([string]$cue)
        try {
            if ($cue -eq 'silence-all') { foreach ($p in $players.Values) { $p.Stop() }; return }
            if ($players.ContainsKey($cue)) { $players[$cue].Play() }
        }
        catch { }   # dźwięk nigdy nie może przerwać animacji
    }.GetNewClosure()
}

function New-MuthurConsoleIO {
    <# Wejście i wyjście animacji. Testy podstawiają własną implementację. #>
    param(
        [string]$InstallRoot = $script:DefaultInstallRoot,
        [bool]$Sound = $true
    )
    $pacer = New-MuthurPacer
    [pscustomobject]@{
        Write      = { param([string]$s) [Console]::Write($s) }
        Sleep      = $pacer
        ResetClock = { & $pacer -1 }.GetNewClosure()
        KeyPressed = {
            if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); return $true }
            $false
        }
        Sound      = New-MuthurSoundBank -SoundsDir (Join-Path $InstallRoot 'plugin\muthur\sounds') -Enabled $Sound
        Width      = [Math]::Max(40, [Console]::WindowWidth)
        Height     = [Math]::Max(15, [Console]::WindowHeight)
        Random     = New-Object Random
    }
}

function Get-MuthurTimeline {
    [CmdletBinding()]
    param([string]$Path = (Join-Path $script:DefaultInstallRoot 'runtime\boot-timeline.json'))
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-MuthurStagePlan {
    <#
    [Stage, Start, Ms] dla trybu. Etap 'ready' trwa len(tekst) × charMs + readyHoldMs.
    Ta sama reguła jest w tools/build_sounds.py (stage_plan).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Timeline,
        [ValidateSet('full', 'short')][string]$Mode = 'full'
    )
    $t = 0
    foreach ($st in $Timeline.$Mode) {
        $ms = if ($st.id -eq 'ready') {
            $Timeline.texts.ready.Length * $Timeline.charMs + $Timeline.readyHoldMs
        } else { [int]$st.ms }
        [pscustomobject]@{ Stage = $st; Start = $t; Ms = $ms }
        $t += $ms
    }
}

function Get-MuthurOctagon {
    <# Ośmiokątna grafika „układu” z budzenia monitora (wzór deterministyczny). #>
    param([int]$Rows = 13)
    if ($Rows % 2 -eq 0) { $Rows-- }
    $half = [int](($Rows - 1) / 2)
    $cols = 4 * $half + 1
    $rnd = New-Object Random 2037
    $glyphs = '│', '─', '┼', '╱', '╲', '▪', '┐', '└', '┘', '┌', '·'
    $grid = New-Object 'string[,]' $Rows, $cols
    for ($r = 0; $r -lt $Rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $x = ($c - 2 * $half) / [double](2 * $half)
            $y = ($r - $half) / [double]$half
            $inside = ([Math]::Abs($x) + [Math]::Abs($y)) -le 1.42
            $grid[$r, $c] = if ($inside -and $rnd.NextDouble() -lt 0.55) { $glyphs[$rnd.Next($glyphs.Count)] } else { ' ' }
        }
    }
    , $grid
}

function Invoke-MuthurBoot {
    <#
    .SYNOPSIS
    Odtwarza ekran rozruchowy MU/TH/UR 6000 według harmonogramu. Dowolny klawisz pomija animację.
    .OUTPUTS
    'completed' albo 'skipped'.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'short')][string]$Mode = 'full',
        $IO = (New-MuthurConsoleIO),
        $Palette = (Get-MuthurPaletteRuntime),
        $Timeline = (Get-MuthurTimeline)
    )
    $e = $script:Esc
    $c = @{}
    foreach ($k in 'phosphor', 'phosphorBright', 'phosphorDim', 'phosphorFaint', 'flare', 'underline',
        'lamp', 'lampBright', 'lampOff', 'crt', 'crtBright', 'amber', 'red') {
        $c[$k] = ConvertTo-MuthurAnsi $Palette.$k
    }
    $ulColor = { param([string]$hex) "$e[58;2;$([Convert]::ToInt32($hex.Substring(1,2),16));$([Convert]::ToInt32($hex.Substring(3,2),16));$([Convert]::ToInt32($hex.Substring(5,2),16))m" }
    $ul = "$e[4m$(& $ulColor $Palette.underline)"      # podkreślenie jak w filmie (SGR 4 + kolor 58)
    $ulMint = "$e[4m$(& $ulColor $Palette.phosphorBright)"
    $noUl = "$e[24m"
    $texts = $Timeline.texts
    $W = $IO.Width; $H = $IO.Height

    # Zegar animacji w ms od startu dźwięku. WaitUntil czeka do chwili bezwzględnej,
    # więc drobne opóźnienia rysowania nie kumulują się.
    $clock = @{ t = 0 }
    $waitUntil = {
        param([int]$abs)
        if (& $IO.KeyPressed) { throw 'MUTHUR_SKIP' }
        $d = $abs - $clock.t
        if ($d -gt 0) { & $IO.Sleep $d; $clock.t = $abs }
    }
    $out = { param([string]$s) & $IO.Write $s }
    $at = { param([int]$row, [int]$col) "$e[$row;${col}H" }
    $cls = "$e[0m$e[2J$e[H"

    $readyRow = 3; $left = 5
    $finalScreen = {
        & $out $cls
        & $out "$(& $at $readyRow $left)$($c.phosphorBright)$ul$($texts.ready)$noUl"
        & $out "$(& $at ($readyRow + 2) $left)$($c.flare)▮"
        & $out "$e[0m$e[?25h`r`n`r`n"
    }

    $matrixLine = {
        param([int]$i, [string]$style)
        $row = $texts.matrix[$i]
        $two = $W -ge 62
        $s = "$(& $at (4 + $i) $left)$e[0m$($c.phosphor)$style" + $row[0].PadRight(17) + $row[1].PadRight(10)
        if ($two) { $s += $noUl + ' ' + $row[2].PadRight(18) + $row[3] }
        $s + $noUl
    }

    $result = 'completed'
    & $out "$e[?25l$cls"
    & $IO.Sound "boot_$Mode"
    if ($IO.PSObject.Properties['ResetClock']) { & $IO.ResetClock }   # zegar od chwili startu dźwięku
    $clock.t = 0
    try {
        foreach ($p in (Get-MuthurStagePlan -Timeline $Timeline -Mode $Mode)) {
            $st = $p.Stage; $t0 = $p.Start; $ms = $p.Ms
            & $waitUntil $t0
            switch ($st.id) {
                'access' {
                    & $out $cls
                    & $out "$(& $at 3 $left)$($c.phosphorDim)$($texts.header)"
                    & $out "$(& $at 5 $left)$($c.phosphor)$($texts.access) $($c.lampOff)■"
                    & $waitUntil ($t0 + $st.buttonAtMs)
                    & $out "$(& $at 5 ($left + $texts.access.Length + 1))$($c.lampBright)■"
                    & $waitUntil ($t0 + $st.buttonAtMs + $st.buttonMs)
                    & $out "$(& $at 5 ($left + $texts.access.Length + 1))$($c.lamp)■ $($c.phosphorBright)$($texts.accessOk)"
                }
                'systems' {
                    $k = 0
                    foreach ($chk in $texts.checks) {
                        & $waitUntil ($t0 + $k * $st.lineMs)
                        & $out "$(& $at (7 + $k) $left)$($c.phosphor)$($chk[0]) $($c.phosphorFaint)$('.' * [Math]::Max(2, 32 - $chk[0].Length))"
                        & $waitUntil ($t0 + $k * $st.lineMs + $st.statusOffsetMs)
                        $col = switch ($chk[2]) { 'ok' { $c.phosphorBright } 'warn' { $c.amber } default { $c.red } }
                        & $out " $col$($chk[1])"
                        $k++
                    }
                }
                'room' {
                    & $out $cls
                    $rows = [Math]::Max(3, [Math]::Min(9, $H - 6)); $cols = [Math]::Max(10, [int](($W - 8) / 2))
                    $top = [Math]::Max(2, [int](($H - $rows) / 2) - 1); $lightsMs = [int]$st.lightsMs
                    for ($r = 0; $r -lt $rows; $r++) {
                        & $out "$(& $at ($top + $r) $left)$($c.lampOff)$((@('■') * $cols) -join ' ')"
                    }
                    $cells = @(0..($rows * $cols - 1) | Sort-Object { $IO.Random.Next() })
                    $frames = [Math]::Max(1, [int]($lightsMs / 40))
                    $batch = [Math]::Max(1, [Math]::Ceiling($cells.Count / $frames))
                    $lit = @($c.lamp, $c.lamp, $c.lampBright)
                    for ($f = 0; $f -lt $frames; $f++) {
                        & $waitUntil ($t0 + $f * 40)
                        $sb = New-Object Text.StringBuilder
                        $from = $f * $batch; $to = [Math]::Min($from + $batch, $cells.Count) - 1
                        if ($from -le $to) {
                            foreach ($cell in $cells[$from..$to]) {
                                $rr = [int][Math]::Floor($cell / $cols); $cc = $cell % $cols
                                [void]$sb.Append("$(& $at ($top + $rr) ($left + 2 * $cc))$($lit[$IO.Random.Next($lit.Count)])■")
                            }
                        }
                        & $out $sb.ToString()
                    }
                    # Migotanie lampek do końca etapu (świergot w ścieżce dźwiękowej).
                    $tb = $t0 + $lightsMs
                    & $waitUntil $tb
                    & $out "$(& $at ($top + $rows + 1) ([Math]::Max(1, [int](($W - 13) / 2))))$($c.phosphorBright)MU/TH/UR 6000"
                    while ($tb + 50 -lt $t0 + $ms) {
                        & $waitUntil $tb
                        $sb = New-Object Text.StringBuilder
                        for ($k = 0; $k -lt [Math]::Max(2, [int]($cells.Count / 20)); $k++) {
                            $cell = $cells[$IO.Random.Next($cells.Count)]
                            $rr = [int][Math]::Floor($cell / $cols); $cc = $cell % $cols
                            $sym = if ($IO.Random.Next(3) -eq 0) { "$($c.lampOff)■" } else { "$($lit[$IO.Random.Next($lit.Count)])■" }
                            [void]$sb.Append("$(& $at ($top + $rr) ($left + 2 * $cc))$sym")
                        }
                        & $out $sb.ToString()
                        $tb += 50
                    }
                }
                'crt' {
                    & $out $cls
                    $grid = Get-MuthurOctagon -Rows ([Math]::Min(13, $H - 4))
                    $gr = $grid.GetLength(0); $gc = $grid.GetLength(1)
                    $top = [Math]::Max(1, [int](($H - $gr) / 2)); $lx = [Math]::Max(1, [int](($W - $gc) / 2))
                    $mid = [int](($gc - 1) / 2)
                    # Rysowanie od środkowej kolumny na boki (jak w filmie).
                    for ($d = 0; $d -le $mid; $d++) {
                        & $waitUntil ($t0 + [int]($d * $st.drawMs / ($mid + 1)))
                        $sb = New-Object Text.StringBuilder
                        # Nawiasy są konieczne: w PowerShellu przecinek wiąże silniej niż odejmowanie.
                        foreach ($col in @(($mid - $d), ($mid + $d)) | Select-Object -Unique) {
                            for ($r = 0; $r -lt $gr; $r++) {
                                if ($grid[$r, $col] -ne ' ') {
                                    $tint = if ($IO.Random.Next(5) -eq 0) { $c.crtBright } else { $c.crt }
                                    [void]$sb.Append("$(& $at ($top + $r) ($lx + $col))$tint$($grid[$r, $col])")
                                }
                            }
                        }
                        & $out $sb.ToString()
                    }
                    # Podtrzymanie obrazu z migotaniem (tryl w ścieżce dźwiękowej, 7/s).
                    $tb = $t0 + $st.drawMs
                    while ($tb + 70 -lt $t0 + $ms) {
                        & $waitUntil $tb
                        $sb = New-Object Text.StringBuilder
                        for ($k = 0; $k -lt 12; $k++) {
                            $r = $IO.Random.Next($gr); $col = $IO.Random.Next($gc)
                            if ($grid[$r, $col] -ne ' ') {
                                $tint = if ($IO.Random.Next(2) -eq 0) { $c.crtBright } else { $c.crt }
                                [void]$sb.Append("$(& $at ($top + $r) ($lx + $col))$tint$($grid[$r, $col])")
                            }
                        }
                        & $out $sb.ToString()
                        $tb += 143
                    }
                }
                'matrix' {
                    & $out $cls
                    $nRows = [Math]::Min($texts.matrix.Count, $H - 6)
                    $width = [Math]::Min($W - 2 * $left, 64)
                    # Faza skanowania: jasne linie przemiatają ekran, migają surowe kody.
                    $prev = @()
                    $tb = $t0
                    $step = 0
                    while ($tb -lt $t0 + $st.scanMs) {
                        & $waitUntil $tb
                        $sb = New-Object Text.StringBuilder
                        foreach ($r in $prev) { [void]$sb.Append("$(& $at $r $left)$e[0m$(' ' * $width)") }
                        $down = 3 + ($step * 3) % ($nRows + 2); $up = 3 + $nRows + 1 - (($step * 2) % ($nRows + 2))
                        for ($k = 0; $k -lt 4; $k++) {
                            $code = $texts.scanCodes[$IO.Random.Next($texts.scanCodes.Count)]
                            $rr = 3 + $IO.Random.Next($nRows + 1); $cc = $left + $IO.Random.Next([Math]::Max(1, $width - 8))
                            [void]$sb.Append("$(& $at $rr $cc)$($c.phosphor)$code")
                        }
                        [void]$sb.Append("$(& $at $down $left)$($c.underline)$('─' * $width)")
                        [void]$sb.Append("$(& $at $up $left)$($c.phosphorBright)$('─' * $width)")
                        $prev = @($down, $up)
                        & $out $sb.ToString()
                        $tb += 50; $step++
                    }
                    # Tabela: wiersze wpisują się kolejno, świeży wiersz ma białe podkreślenie.
                    & $waitUntil ($t0 + $st.scanMs)
                    & $out $cls
                    & $out "$(& $at 2 $left)$($c.phosphor)$($texts.matrixTitle)"
                    $span = $st.tableMs - $st.scanMs
                    for ($i = 0; $i -lt $nRows; $i++) {
                        & $waitUntil ($t0 + $st.scanMs + [int]($i * $span / $nRows))
                        if ($i -gt 0) { & $out (& $matrixLine ($i - 1) '') }
                        & $out (& $matrixLine $i $ul)
                    }
                    & $waitUntil ($t0 + $st.tableMs)
                    & $out (& $matrixLine ($nRows - 1) '')
                    # Czyste piski 11/s: mały kursor błyska w ich rytmie.
                    $tb = $t0 + $st.tableMs; $on = $true
                    while ($tb + 30 -lt $t0 + $ms) {
                        & $waitUntil $tb
                        & $out "$(& $at (5 + $nRows) $left)$(if ($on) { "$($c.underline)▮" } else { ' ' })"
                        $on = -not $on
                        $tb += [int](1000 / 11)
                    }
                    & $out "$(& $at (5 + $nRows) $left) "
                }
                'select' {
                    # Podkreślenie na DOWODZENIE, potem przeskok na INTERFEJS 2037; miga w rytmie bloków dźwięku.
                    $tb = $t0; $k = 0
                    while ($tb -lt $t0 + $ms - 60) {
                        & $waitUntil $tb
                        $target = if ($tb -lt $t0 + $st.jumpAtMs) { [int]$texts.matrixFrom } else { [int]$texts.matrixTo }
                        $other = if ($target -eq [int]$texts.matrixFrom) { [int]$texts.matrixTo } else { [int]$texts.matrixFrom }
                        & $out (& $matrixLine $other '')
                        & $out (& $matrixLine $target $(if ($k % 2 -eq 0) { $ul } else { $ulMint }))
                        $tb += 110; $k++
                    }
                }
                'clear' {
                    & $out $cls
                }
                'ready' {
                    & $out $cls
                    $text = $texts.ready
                    for ($i = 0; $i -lt $text.Length; $i++) {
                        & $waitUntil ($t0 + $i * $Timeline.charMs)
                        $s = "$(& $at $readyRow ($left + $i))"
                        # Nowy znak rozbłyska (żółtozielony), poprzedni gaśnie do koloru tekstu.
                        if ($i -gt 0) { $s = "$(& $at $readyRow ($left + $i - 1))$($c.phosphorBright)$ul$($text[$i - 1])" + $s }
                        & $out "$s$($c.flare)$ul$($text[$i])$noUl"
                    }
                    & $waitUntil ($t0 + $text.Length * $Timeline.charMs)
                    & $out "$(& $at $readyRow ($left + $text.Length - 1))$($c.phosphorBright)$ul$($text[$text.Length - 1])$noUl"
                    & $out "$(& $at ($readyRow + 2) $left)$($c.flare)▮"
                }
            }
        }
        $total = 0; foreach ($p in (Get-MuthurStagePlan -Timeline $Timeline -Mode $Mode)) { $total += $p.Ms }
        & $waitUntil $total
    }
    catch {
        if ($_.Exception.Message -ne 'MUTHUR_SKIP') { & $IO.Sound 'silence-all'; & $out "$e[0m$e[?25h"; throw }
        $result = 'skipped'
        & $IO.Sound 'silence-all'
    }
    & $finalScreen
    $result
}

# ─── Polecenia dla użytkownika ───────────────────────────────────────────────

function Invoke-MuthurClaude {
    <#
    .SYNOPSIS
    Uruchamia claude: z motywem MU/TH/UR, gdy jest włączony, albo bez zmian.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Arguments = @(),
        [string]$InstallRoot = $script:DefaultInstallRoot,
        [string]$ClaudeExe,
        [scriptblock]$Runner = { param($exe, $argv) & $exe @argv },
        $IO,
        [switch]$Interactive = (-not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected),
        [datetime]$Today = (Get-Date)
    )
    if (-not $ClaudeExe) { $ClaudeExe = Get-MuthurClaudeExe }
    $state = Get-MuthurState -InstallRoot $InstallRoot
    $installed = Test-Path -LiteralPath (Join-Path $InstallRoot 'plugin\muthur')

    if (-not $state.enabled -or -not $installed -or $env:MUTHUR_DISABLE -eq '1' -or (Test-MuthurPassthrough $Arguments)) {
        & $Runner $ClaudeExe $Arguments
        return
    }

    $palette = Get-MuthurPaletteRuntime -InstallRoot $InstallRoot
    $recolor = $Interactive -and $state.recolorOtherTerminals -and ($env:MUTHUR_TERMINAL -ne '1') -and (Test-MuthurCanRecolor)
    $write = if ($IO) { $IO.Write } else { { param([string]$s) [Console]::Write($s) } }

    try {
        if ($Interactive -and -not (Test-MuthurPrintMode $Arguments)) {
            $realConsole = -not $IO
            if ($realConsole) {
                Enable-MuthurVirtualTerminal
                $IO = New-MuthurConsoleIO -InstallRoot $InstallRoot -Sound ([bool]$state.sound)
                $write = $IO.Write
            }
            if ($recolor) { & $write (Get-MuthurOscPalette -Palette $palette) }
            $mode = Get-MuthurBootMode -State $state -Today $Today
            $timeline = Get-MuthurTimeline -Path (Join-Path $InstallRoot 'runtime\boot-timeline.json')
            $boot = { [void](Invoke-MuthurBoot -Mode $mode -IO $IO -Palette $palette -Timeline $timeline) }
            if ($realConsole) { Invoke-MuthurWithUtf8Console $boot } else { & $boot }
            if ($mode -eq 'full') {
                $state.lastFullBoot = $Today.ToString('yyyy-MM-dd')
                Set-MuthurState -State $state -InstallRoot $InstallRoot
            }
        }
        elseif ($recolor) { & $write (Get-MuthurOscPalette -Palette $palette) }

        & $Runner $ClaudeExe (Get-MuthurClaudeArguments -InstallRoot $InstallRoot -Arguments $Arguments)
    }
    finally {
        if ($recolor) { & $write (Get-MuthurOscReset) }
    }
}

function claude {
    # Nakładka na claude.exe (zwykła funkcja, żeby wszystkie argumenty, także -p, przeszły bez zmian).
    Invoke-MuthurClaude -Arguments $args
}

function muthur {
    <#
    .SYNOPSIS
    muthur on | off | status | boot [full|short] | sound [on|off]
    #>
    param(
        [ValidateSet('on', 'off', 'status', 'boot', 'sound', 'help')][string]$Command = 'status',
        [ValidateSet('full', 'short', 'on', 'off', '')][string]$Mode = '',
        [string]$InstallRoot = $script:DefaultInstallRoot
    )
    $state = Get-MuthurState -InstallRoot $InstallRoot
    switch ($Command) {
        'on' {
            $state.enabled = $true
            Set-MuthurState -State $state -InstallRoot $InstallRoot
            'MU/TH/UR 6000: MOTYW AKTYWNY. NASTĘPNE URUCHOMIENIE claude OTWORZY INTERFEJS 2037.'
        }
        'off' {
            $state.enabled = $false
            Set-MuthurState -State $state -InstallRoot $InstallRoot
            'MU/TH/UR 6000: MOTYW WYŁĄCZONY. claude DZIAŁA W TRYBIE STANDARDOWYM.'
        }
        'status' {
            $installed = Test-Path -LiteralPath (Join-Path $InstallRoot 'plugin\muthur')
            "MU/TH/UR 6000 · RAPORT STANU"
            "  MOTYW ............. $(if ($state.enabled) { 'AKTYWNY' } else { 'WYŁĄCZONY' })"
            "  PLUGIN ............ $(if ($installed) { 'ZAINSTALOWANY' } else { 'BRAK (uruchom install.ps1)' })"
            "  DŹWIĘK ............ $(if ($state.sound) { 'AKTYWNY' } else { 'WYCISZONY' })"
            "  PROFIL TERMINALA .. $(if ($env:MUTHUR_TERMINAL -eq '1') { 'MU/TH/UR 6000' } else { 'INNY' })"
            "  OSTATNI PEŁNY ROZRUCH: $(if ($state.lastFullBoot) { $state.lastFullBoot } else { 'NIGDY' })"
        }
        'sound' {
            if ($Mode -eq 'on' -or $Mode -eq 'off') {
                $state.sound = ($Mode -eq 'on')
                Set-MuthurState -State $state -InstallRoot $InstallRoot
            }
            "MU/TH/UR 6000: DŹWIĘK $(if ($state.sound) { 'AKTYWNY' } else { 'WYCISZONY' })."
        }
        'boot' {
            $bootMode = if ($Mode -eq 'short') { 'short' } else { 'full' }
            Enable-MuthurVirtualTerminal
            $palette = Get-MuthurPaletteRuntime -InstallRoot $InstallRoot
            $io = New-MuthurConsoleIO -InstallRoot $InstallRoot -Sound ([bool]$state.sound)
            $timeline = Get-MuthurTimeline -Path (Join-Path $InstallRoot 'runtime\boot-timeline.json')
            Invoke-MuthurWithUtf8Console { [void](Invoke-MuthurBoot -Mode $bootMode -IO $io -Palette $palette -Timeline $timeline) }
        }
        'help' {
            'muthur on          włącza motyw MU/TH/UR dla polecenia claude'
            'muthur off         wyłącza motyw'
            'muthur status      pokazuje stan motywu'
            'muthur boot        odtwarza ekran rozruchowy (muthur boot short: wersja krótka)'
            'muthur sound off   wycisza dźwięki (muthur sound on: przywraca)'
        }
    }
}

Export-ModuleMember -Function Get-MuthurState, Set-MuthurState, Get-MuthurBootMode, Test-MuthurPassthrough,
    Test-MuthurPrintMode, Get-MuthurClaudeArguments, Get-MuthurOscPalette, Get-MuthurOscReset,
    Get-MuthurTimeline, Get-MuthurStagePlan, Get-MuthurOctagon, Invoke-MuthurBoot, Invoke-MuthurClaude,
    Invoke-MuthurWithUtf8Console, New-MuthurPacer, New-MuthurSoundBank, claude, muthur
