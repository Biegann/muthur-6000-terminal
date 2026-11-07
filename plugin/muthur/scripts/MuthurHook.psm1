#Requires -Version 5.1
# Logika hooków i paska statusu pluginu MU/TH/UR 6000.
Set-StrictMode -Version Latest

$script:Esc = [char]27

# Wołacz „Matko” w dowolnym miejscu wiadomości.
$script:VocativePattern = '(?i)(?<!\p{L})(matko|matuchno)(?!\p{L})'
# „Matka”, „Mother”, „MU/TH/UR” na początku wiadomości, użyte jak imię, czyli
# z przecinkiem, dwukropkiem, ?, ! lub kropką za sobą albo na końcu wiadomości.
# Opcjonalnie poprzedzone powitaniem.
$script:AddressPattern = '(?i)^\s*(?:(?:hej|hey|ok|okej|dobra|no|witaj|cześć|czesc)[\s,!]+)?' +
    '(?:matka|mother|mu\s*[/\-.]?\s*th\s*[/\-.]?\s*ur)' +
    '(?=\s*(?:[,:;!?.…]|$))'

function Test-MuthurAddress {
    <#
    .SYNOPSIS
    Sprawdza, czy wiadomość zwraca się do asystenta jako do MATKI (MU/TH/UR).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][string]$Prompt)
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return $false }
    return ($Prompt -match $script:VocativePattern) -or ($Prompt -match $script:AddressPattern)
}

function Get-MuthurPromptHookOutput {
    <#
    .SYNOPSIS
    Zwraca JSON dla hooka UserPromptSubmit albo $null, gdy wiadomość nie jest do MATKI.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$HookInputJson)
    try { $data = $HookInputJson | ConvertFrom-Json } catch { return $null }
    $prompt = if ($data.PSObject.Properties['prompt']) { [string]$data.prompt } else { '' }
    if (-not (Test-MuthurAddress -Prompt $prompt)) { return $null }
    $context = 'Tryb MU/TH/UR: w tej wiadomości użytkownik zwrócił się do asystenta jako do MATKI ' +
        '(MU/TH/UR 6000). Według stylu motywu ta odpowiedź ma formę interfejsu MATKI.'
    [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = $context
        }
    } | ConvertTo-Json -Depth 4 -Compress
}

function Format-MuthurStatusLine {
    <#
    .SYNOPSIS
    Buduje pasek statusu w stylu MU/TH/UR z danych JSON od Claude Code.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$StatusJson,
        [datetime]$Now = (Get-Date)
    )
    try { $data = $StatusJson | ConvertFrom-Json } catch { $data = $null }

    function Get-Field($obj, [string[]]$path) {
        foreach ($p in $path) {
            if ($null -eq $obj -or -not $obj.PSObject.Properties[$p]) { return $null }
            $obj = $obj.$p
        }
        $obj
    }

    $model = Get-Field $data 'model', 'display_name'
    $dir = Get-Field $data 'workspace', 'current_dir'
    if (-not $dir) { $dir = Get-Field $data 'cwd' }
    $pct = Get-Field $data 'context_window', 'used_percentage'

    $e = $script:Esc
    $bright = "$e[92m"; $normal = "$e[32m"; $dim = "$e[90m"; $amber = "$e[33m"; $red = "$e[31m"; $reset = "$e[0m"
    $sep = "$dim │ $normal"

    # Krótko: szeroki font MUTHUR Mono mieści mniej znaków w linii.
    $parts = @("$bright▮ MU/TH/UR 6000$normal")
    if ($model) { $parts += ([string]$model).ToUpperInvariant() }
    if ($dir) {
        $leaf = Split-Path ([string]$dir -replace '/', '\') -Leaf
        if ($leaf) { $parts += $leaf.ToUpperInvariant() }
    }
    if ($null -ne $pct) {
        $value = [int][math]::Floor([double]$pct)
        $color = if ($value -ge 90) { $red } elseif ($value -ge 75) { $amber } else { $normal }
        $parts += "${color}PAMIĘĆ $value%$normal"
    }
    # Akcja filmu toczy się w 2122 roku.
    $parts += $Now.ToString('dd.MM.') + '2122 ' + $Now.ToString('HH:mm')

    $normal + ($parts -join $sep) + $reset
}

Export-ModuleMember -Function Test-MuthurAddress, Get-MuthurPromptHookOutput, Format-MuthurStatusLine
