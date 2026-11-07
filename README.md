# MU/TH/UR 6000: motyw dla Claude Code

Nakładka, dzięki której praca z Claude Code wygląda jak rozmowa z MATKĄ, komputerem statku USCSS Nostromo z filmu „Obcy – 8. pasażer Nostromo” (1979). Wszystkie komunikaty są po polsku.

Projekt fanowski. Nie zawiera materiałów z filmu: font, dźwięki i grafika powstają w tym repozytorium.

Działa w Windows 10/11. Pełny motyw potrzebuje Windows Terminal i PowerShella.

## Szybka instalacja: sam plugin

Kolory, tryb MATKI, spinner `▮`, panel lampek `/muthur` i dźwięki sesji. Bez fontu, efektu CRT i ekranu rozruchowego.

W sesji Claude Code wpisz:

```
/plugin install muthur --marketplace Biegann/muthur-6000-terminal
```

Na pytanie `Add marketplace?` odpowiedz `y`, a potem wybierz zakres instalacji (Enter wybiera zakres użytkownika).

Z wiersza poleceń:

```
claude plugin install muthur --marketplace Biegann/muthur-6000-terminal
```

W aplikacji desktopowej (tam `/plugin` nie działa) kliknij + obok pola promptu, potem Plugins i Add marketplace z `Biegann/muthur-6000-terminal`, a na końcu Add plugin.

Kolory włączysz w `/theme`, wybierając motyw `muthur`. Czasowniki spinnera, podpowiedzi i pasek statusu ustawia dopiero pełna instalacja.

## Pełna instalacja: cały motyw

Potrzebne są Python 3.11 lub nowszy oraz .NET Framework 4 (jest w każdym Windows 10/11). W sklonowanym repozytorium uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Potem otwórz w Windows Terminal profil „MU/TH/UR 6000” i wpisz `muthur on`, a następnie `claude`.

## Etapy

| Etap | Zakres | Stan |
|---|---|---|
| 0 | Kalibracja na klatkach z filmu | ✅ |
| 1 | Font MUTHUR Mono, shader CRT, profil Windows Terminal | ✅ |
| 2 | Plugin Claude Code: kolory, persona MATKI, spinner, pasek statusu | ✅ |
| 3 | Nakładka na `claude`, ekran rozruchowy, `muthur on/off` | ✅ |
| 4 | Dźwięki | ✅ |
| 5 | Mod: ściana lampek, etykiety | ✅ |

## Co robi instalator (etap 1)

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Skrypt:
- buduje font,
- instaluje go dla bieżącego użytkownika (nie wymaga uprawnień administratora),
- kopiuje shader do `%LOCALAPPDATA%\MUTHUR`,
- dodaje profil „MU/TH/UR 6000” jako fragment Windows Terminal. Twój `settings.json` zostaje bez zmian.

Odinstalowanie: `.\uninstall.ps1`.

## Plugin Claude Code (etap 2)

Plugin `plugin/muthur` zawiera:
- **Motyw** `themes/muthur.json`: generowany z `config/palette.json` przez `tools/build_claude_theme.py`.
- **Osobowość MATKI** `output-styles/matka.md`: zwykła praca po polsku. Po zwrocie „Matko” (albo „Matka,”, „Mother,”, „MU/TH/UR:” na początku wiadomości) odpowiedź ma formę interfejsu MU/TH/UR.
- **Hook** `UserPromptSubmit`: wykrywa zwrot do MATKI i oznacza wiadomość dla modelu.
- **Pasek statusu** `scripts/statusline.ps1`: system, statek, model, katalog, zużycie pamięci kontekstu i data w 2122 roku.

Ustawienia sesji (motyw, czasowniki spinnera, podpowiedzi, pasek statusu) trafiają do `%LOCALAPPDATA%\MUTHUR\claude-settings.json`. Twoje `~/.claude/settings.json` zostaje nietknięte.

## Polecenie `muthur` i nakładka na `claude` (etap 3)

Instalator dopisuje do profilu Windows PowerShella (`$PROFILE`) oznaczony blok `# >>> MU/TH/UR 6000 >>>`, który ładuje moduł z `%LOCALAPPDATA%\MUTHUR\runtime`. Reszta profilu zostaje bez zmian.

| Polecenie | Działanie |
|---|---|
| `muthur on` / `muthur off` | włącza i wyłącza motyw dla `claude` (stan w `%LOCALAPPDATA%\MUTHUR\state.json`) |
| `muthur status` | raport stanu |
| `muthur boot` / `muthur boot short` | odtwarza ekran rozruchowy bez uruchamiania Claude |

Gdy motyw jest włączony, `claude`:
1. Odtwarza ekran rozruchowy. Pełny (ok. 8,4 s: autoryzacja, test systemów, ściana lampek w pokoju MATKI, macierz adresowa, „INTERFEJS 2037 GOTOWY DO ZAPYTAŃ”) przy pierwszym uruchomieniu danego dnia, potem krótki (ok. 4,1 s, lampki i schemat). Dowolny klawisz pomija animację.
2. Poza profilem „MU/TH/UR 6000” przekolorowuje kartę na paletę fosforu (OSC 4/10/11/12) i przywraca kolory po wyjściu.
3. Uruchamia `claude.exe` z `--plugin-dir` i `--settings` motywu.

Bez zmian (i bez motywu) przechodzą: podpolecenia (`mcp`, `plugin`, `update`, `doctor`, …), `--version` i `--help`. W trybie `-p` motyw działa bez animacji. Jednorazowe wyłączenie: `$env:MUTHUR_DISABLE = '1'`.

Nakładka działa w PowerShellu. W cmd i Git Bash `claude` uruchamia się bez motywu.

## Dźwięki i synchronizacja (etap 4)

Dźwięki syntezuje `tools/build_sounds.py` (WAV 44,1 kHz, sama biblioteka standardowa, stałe ziarno, więc wynik jest powtarzalny). Nie ma w nich nagrań z filmu. Barwy i rytmy dobrano według pomiarów sceny z MATKĄ (`tools/analyze_reference.py`, nagranie w `reference/`, poza repozytorium): tło pomieszczenia 150/65 Hz, przycisk dostępu z harmonicznymi 245 Hz, ton macierzy 759 Hz pulsujący 6,8/s, stuki liter 2,4–3,0 kHz.

**Synchronizacja.** `config/boot-timeline.json` to jeden harmonogram rozruchu: etapy, czasy w ms i teksty. Z niego powstaje ścieżka dźwiękowa (`boot_full.wav`, `boot_short.wav`) i według niego animacja wyświetla każde zdarzenie w chwili bezwzględnej od startu dźwięku. Testy sprawdzają, że PowerShell i Python liczą te same czasy, a każda litera pojawia się w chwili swojego stuku.

Etapy pełnego rozruchu (ok. 8,4 s), jak w filmie: autoryzacja dostępu → test systemów → ściana lampek pokoju MATKI → ośmiokątna grafika na monitorze → MACIERZ ADRESOWA NADZORU (skan i tabela) → wybór INTERFEJS 2037 → czyszczenie ekranu → „INTERFEJS 2037 GOTOWY DO ZAPYTAŃ”.

| Sesja Claude Code | Dźwięk |
|---|---|
| Zwrot „Matko” | `inquiry`: klawisze konsoli (pisk 2982 Hz) |
| Użycie narzędzia | `tool`: cichy pisk |
| Koniec odpowiedzi | `transmission_short/medium/long`: stukot liter zależny od długości odpowiedzi i zatrzask |
| Claude czeka na Ciebie | `attention`: przycisk dostępu |
| Błąd narzędzia / błąd API | `error` / `alert` |

W sesji Claude Code hooki uruchamiają asynchronicznie `muthur-play.exe`, mały odtwarzacz kompilowany przez `tools/build_player.ps1` wbudowanym w Windows kompilatorem C# (źródło: `player/MuthurPlay.cs`).

Gotowe dźwięki i odtwarzacz leżą też w `plugin/muthur/sounds` i `plugin/muthur/player`, bo instalacja z marketplace'u nie uruchamia `install.ps1`. Po zmianie dźwięków lub odtwarzacza uruchom `tools/stage_plugin_assets.ps1`. Test pilnuje, że kopie w pluginie są aktualne.

- `muthur sound off` / `muthur sound on`: wycisza i przywraca dźwięki.
- Diagnostyka: `$env:MUTHUR_PLAY_LOG = 'C:\ścieżka\play.log'` przed `claude` zapisuje każde wywołanie odtwarzacza.
- Podgląd klatek animacji bez terminala: `tools/render_boot_frames.py` (emulator `pyte`).

## Mod Claude Code (etap 5)

`plugin/muthur/hooks/register.tsx` to moduł (mod) ładowany razem z pluginem:

- **Spinner** kończy się blokowym kursorem MATKI `▮` zamiast wielokropka.
- **Linia końca tury** to `TRANSMISJA ZAKOŃCZONA · 3 s` zamiast „Baked for 3s”.
- **Odpowiedź w trybie MATKI** ma nad treścią etykietę `▮ MU/TH/UR 6000` i podkreślony nagłówek `INTERFEJS 2037 · ZAPYTANIE PRZYJĘTE`. Zapisana wiadomość się nie zmienia, zmienia się tylko rysunek.
- **`/muthur`** otwiera i zamyka panel „POKÓJ MATKI” ze ścianą bursztynowych lampek (`Raster`). Lampki migają spokojnie, a szybciej, gdy Claude pracuje. Pod spodem jest stan (`GOTOWY DO ZAPYTAŃ` albo `PRZETWARZANIE`) i podsumowanie ostatniego zapytania: czas, sposób zakończenia oraz tokeny wejścia, wyjścia i pamięci podręcznej (tury subagentów się nie liczą). Panel otwiera się obok rozmowy w trybie pełnoekranowym (`/tui fullscreen`) przy szerokim oknie, a w innym przypadku nad polem promptu.

Testy modu: `claude plugin test` w katalogu `plugin/muthur` (włączone do `tests/run-all.ps1`).

## Testy

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-all.ps1
```

Uruchamia testy Pythona (unittest), kompiluje shader (`fxc` z Windows SDK) i odpala testy PowerShella (Pester 3.4). Bez zaliczonych testów nie robimy commitów.

Skrypty PowerShella muszą mieć BOM UTF-8, bo Windows PowerShell 5.1 inaczej psuje polskie znaki. Test to sprawdza, a naprawia `python tools/add_bom.py`.

## Licencje

- **Kod, dźwięki i pozostałe pliki:** GNU General Public License v3.0 (`LICENSE`).
- **MUTHUR Mono:** font pochodny [Space Mono](https://github.com/googlefonts/spacemono) (SIL Open Font License 1.1, `vendor/spacemono/OFL.txt`), rozciągnięty w poziomie o 35%. Zmieniona nazwa zgodnie z wymogami OFL.
