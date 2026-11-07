# Uruchamia wszystkie testy projektu. Kod wyjścia 0 tylko wtedy, gdy wszystkie przeszły.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$failed = @()

Write-Host '== Python (unittest) ==' -ForegroundColor Green
$env:PYTHONIOENCODING = 'utf-8'
& (Join-Path $repo '.venv\Scripts\python.exe') -m unittest discover -s (Join-Path $repo 'tests\python')
if ($LASTEXITCODE -ne 0) { $failed += 'python' }

Write-Host '== Shader HLSL (fxc) ==' -ForegroundColor Green
$fxc = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter fxc.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\x64' } | Select-Object -First 1
if (-not $fxc) {
    Write-Host 'Brak fxc.exe (Windows SDK): pomijam kompilację shadera.' -ForegroundColor Yellow
} else {
    $tmp = Join-Path $env:TEMP 'muthur-crt-test.cso'
    & $fxc.FullName /nologo /T ps_4_0 /E main /Fo $tmp (Join-Path $repo 'terminal\muthur-crt.hlsl')
    if ($LASTEXITCODE -ne 0) { $failed += 'shader' }
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

Write-Host '== Plugin Claude Code (claude plugin validate) ==' -ForegroundColor Green
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $validate = claude plugin validate (Join-Path $repo 'plugin\muthur') 2>&1
    if ($LASTEXITCODE -ne 0) { $validate | Write-Host; $failed += 'plugin' }
    else { Write-Host ($validate | Select-Object -Last 1) }

    Write-Host '== Mod Claude Code (claude plugin test) ==' -ForegroundColor Green
    Push-Location (Join-Path $repo 'plugin\muthur')
    try {
        $modTests = claude plugin test 2>&1
        $modCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    $modTests | Select-Object -Last 4 | ForEach-Object { Write-Host $_ }
    if ($modCode -ne 0) { $modTests | Write-Host; $failed += 'mod' }
} else {
    Write-Host 'Brak polecenia claude: pomijam walidację pluginu.' -ForegroundColor Yellow
}

Write-Host '== PowerShell (Pester) ==' -ForegroundColor Green
$pester = Invoke-Pester -Path (Join-Path $repo 'tests\powershell') -PassThru
if ($pester.FailedCount -gt 0) { $failed += 'pester' }

if ($failed.Count -gt 0) {
    Write-Host "TESTY NIEZALICZONE: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'WSZYSTKIE TESTY ZALICZONE' -ForegroundColor Green
exit 0
