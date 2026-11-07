# Uruchamiany przez profil „MU/TH/UR 6000” w Windows Terminal.
# Oznacza powłokę i przestawia kolory PSReadLine na odcienie luminoforu.
$env:MUTHUR_TERMINAL = '1'

if (Get-Module -ListAvailable -Name PSReadLine) {
    # Nazwy ConsoleColor trafiają do palety ANSI schematu „MU/TH/UR 6000”:
    # Green = jasny fosfor, DarkGreen = fosfor, DarkGray = przygaszony, Yellow = bursztyn.
    Set-PSReadLineOption -Colors @{
        Default   = 'DarkGreen'
        Command   = 'Green'
        Keyword   = 'Green'
        Parameter = 'DarkCyan'
        String    = 'Cyan'
        Number    = 'Cyan'
        Variable  = 'Green'
        Operator  = 'DarkGreen'
        Type      = 'DarkCyan'
        Member    = 'DarkGreen'
        Comment   = 'DarkGray'
        Emphasis  = 'Yellow'
        Error     = 'Red'
    }
}
