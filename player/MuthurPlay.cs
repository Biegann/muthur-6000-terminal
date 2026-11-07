// muthur-play.exe: odtwarzacz dźwięków MU/TH/UR 6000 dla hooków Claude Code.
//
// Użycie: muthur-play.exe <dźwięk> [--dry-run]
//   <dźwięk>  nazwa pliku z katalogu ..\sounds bez .wav (np. attention, error)
//   stop      czyta JSON hooka Stop ze stdin i wybiera transmission_short/medium/long
//             według długości ostatniej odpowiedzi
//   --dry-run wypisuje ścieżkę pliku zamiast odtwarzać (do testów)
//
// Program jest kompilowany kompilatorem C# wbudowanym w .NET Framework 4, uruchamia się
// w kilkadziesiąt ms i nigdy nie zgłasza błędów: dźwięk nie może zepsuć sesji.
// Nie gra, gdy w state.json motywu jest "sound": false.
using System;
using System.IO;
using System.Media;
using System.Text;
using System.Text.RegularExpressions;

static class MuthurPlay
{
    static int Main(string[] args)
    {
        try
        {
            bool dryRun = Array.IndexOf(args, "--dry-run") >= 0;
            string cue = null;
            foreach (string a in args) { if (!a.StartsWith("--")) { cue = a; break; } }
            if (cue == null || !Regex.IsMatch(cue, "^[a-z0-9_]+$")) return 0;

            // Układ instalacji: <InstallRoot>\plugin\muthur\player\muthur-play.exe
            string playerDir = AppDomain.CurrentDomain.BaseDirectory;
            string pluginRoot = Path.GetFullPath(Path.Combine(playerDir, ".."));
            string installRoot = Environment.GetEnvironmentVariable("MUTHUR_HOME");
            if (string.IsNullOrEmpty(installRoot))
                installRoot = Path.GetFullPath(Path.Combine(pluginRoot, "..", ".."));

            string state = Path.Combine(installRoot, "state.json");
            if (File.Exists(state) && Regex.IsMatch(File.ReadAllText(state), "\"sound\"\\s*:\\s*false"))
            {
                if (dryRun) Console.WriteLine("WYCISZONE");
                return 0;
            }

            if (cue == "stop")
            {
                var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);
                int len = LastMessageLength(reader.ReadToEnd());
                cue = len < 300 ? "transmission_short" : len < 1500 ? "transmission_medium" : "transmission_long";
            }

            string wav = Path.Combine(pluginRoot, "sounds", cue + ".wav");
            // Diagnostyka: MUTHUR_PLAY_LOG=<plik> zapisuje każde wywołanie.
            string log = Environment.GetEnvironmentVariable("MUTHUR_PLAY_LOG");
            if (!string.IsNullOrEmpty(log))
                File.AppendAllText(log, DateTime.Now.ToString("HH:mm:ss.fff") + " " + cue + (File.Exists(wav) ? "" : " (brak pliku)") + Environment.NewLine);
            if (!File.Exists(wav)) return 0;
            if (dryRun) { Console.WriteLine(wav); return 0; }
            using (var player = new SoundPlayer(wav)) { player.PlaySync(); }
        }
        catch { }
        return 0;
    }

    static int LastMessageLength(string json)
    {
        Match m = Regex.Match(json ?? "", "\"last_assistant_message\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
        return m.Success ? m.Groups[1].Value.Length : 0;
    }
}
