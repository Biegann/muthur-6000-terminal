import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_sounds  # noqa: E402

# Ścieżki rozruchu i dźwięki hooków pluginu (hooks.json, prompt-submit.ps1, muthur-play.exe).
REQUIRED = {
    "boot_full", "boot_short",
    "inquiry", "transmission_short", "transmission_medium", "transmission_long",
    "tool", "attention", "error", "alert",
}
MAX_LEN = {"tool": 0.05, "attention": 1.0, "transmission_long": 2.0, "inquiry": 0.6}


def read(path):
    with wave.open(str(path), "rb") as w:
        params = (w.getnchannels(), w.getsampwidth(), w.getframerate())
        n = w.getnframes()
        data = w.readframes(n)
    return params, n / build_sounds.RATE, struct.unpack(f"<{n}h", data)


class BuildSoundsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.paths = {p.stem: p for p in build_sounds.build(Path(cls.tmp.name))}
        cls.tl = build_sounds.load_timeline()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_all_cues_present_and_nothing_else(self):
        self.assertEqual(set(self.paths), REQUIRED)

    def test_format_and_session_lengths(self):
        for name, path in self.paths.items():
            params, seconds, _ = read(path)
            self.assertEqual(params, (1, 2, 44100), name)
            if name in MAX_LEN:
                self.assertLessEqual(seconds, MAX_LEN[name], name)

    def test_boot_tracks_last_exactly_as_long_as_the_animation(self):
        # Animacja (MuthurRuntime.psm1) czyta ten sam harmonogram; długości muszą się zgadzać.
        for mode in ("full", "short"):
            _, seconds, _ = read(self.paths[f"boot_{mode}"])
            self.assertAlmostEqual(seconds * 1000, build_sounds.total_ms(self.tl, mode), delta=2)

    def test_full_boot_is_about_8_to_9_seconds(self):
        self.assertTrue(8000 <= build_sounds.total_ms(self.tl, "full") <= 9000)

    def test_ready_stage_formula(self):
        plan = build_sounds.stage_plan(self.tl, "full")
        sid, start, ms = plan[-1][0]["id"], plan[-1][1], plan[-1][2]
        self.assertEqual(sid, "ready")
        self.assertEqual(ms, len(self.tl["texts"]["ready"]) * self.tl["charMs"] + self.tl["readyHoldMs"])
        self.assertEqual(start, sum(st["ms"] for st in self.tl["full"][:-1]))

    def test_typing_ticks_land_on_letters(self):
        # W etapie „ready” każda litera (nie spacja) ma stuk dokładnie w swojej chwili.
        _, _, samples = read(self.paths["boot_short"])
        plan = build_sounds.stage_plan(self.tl, "short")
        start = plan[-1][1]
        text = self.tl["texts"]["ready"]
        rate = build_sounds.RATE

        def energy(ms_from, ms_to):
            a, b = int(rate * ms_from / 1000), int(rate * ms_to / 1000)
            seg = samples[a:b]
            return sum(x * x for x in seg) / max(1, len(seg))

        for i, ch in enumerate(text):
            t = start + i * self.tl["charMs"]
            if ch == " ":
                self.assertLess(energy(t, t + 20), energy(t - self.tl["charMs"], t - self.tl["charMs"] + 20) + 1,
                                "spacja nie stuka")
            else:
                self.assertGreater(energy(t, t + 20), 10_000, f"brak stuku przy literze {i} „{ch}”")

    def test_session_sounds_are_low(self):
        # Życzenie użytkownika: w rozmowie z Claude niższe brzmienia z animacji, bez wysokich pisków.
        # Przybliżenie środka widma: częstość przejść przez zero (Hz) na niezerowych próbkach.
        def zero_cross_hz(samples):
            s = [x for x in samples if x != 0]
            z = sum(1 for a, b in zip(s, s[1:]) if (a < 0) != (b < 0))
            return z / 2 / (len(s) / build_sounds.RATE)
        for name in ("inquiry", "transmission_short", "transmission_medium", "transmission_long",
                     "tool", "attention", "error", "alert"):
            _, _, samples = read(self.paths[name])
            self.assertLess(zero_cross_hz(samples), 1200, f"{name}: za wysoko")

    def test_not_clipping_and_audible(self):
        for name, path in self.paths.items():
            _, _, samples = read(path)
            peak = max(abs(s) for s in samples) / 32767
            self.assertGreater(peak, 0.02, f"{name}: za cicho")
            self.assertLessEqual(peak, 0.43, f"{name}: za głośno")

    def test_transmission_length_grows(self):
        lens = [read(self.paths[f"transmission_{k}"])[1] for k in ("short", "medium", "long")]
        self.assertEqual(lens, sorted(lens))

    def test_reproducible(self):
        with tempfile.TemporaryDirectory() as other:
            again = {p.stem: p for p in build_sounds.build(Path(other))}
            for name in self.paths:
                self.assertEqual(self.paths[name].read_bytes(), again[name].read_bytes(), name)


if __name__ == "__main__":
    unittest.main()
