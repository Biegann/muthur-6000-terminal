"""Syntezuje dźwięki MU/TH/UR 6000 (WAV 44,1 kHz, 16 bit, mono).

Nie zawiera nagrań z filmu. Barwy i rytmy dobrane według pomiarów sceny z MATKĄ
(tools/analyze_reference.py na nagraniu z reference/audio):

  tło pomieszczenia   150 Hz (+300, 450 Hz) i 65 Hz, cicho (ok. -30 dBFS)
  przycisk dostępu    szereg harmonicznych 245 Hz (najmocniej 490 i 737 Hz), ok. 0,9 s, drżenie 43 Hz
  rozruch pamięci     ten sam ton, bramkowany 2,8/s, z terkotem przekaźników
  lampki              świergot ok. 4,5 kHz, 10/s
  budzenie monitora   arpeggio pisków 2,2–3,8 kHz (13/s), potem pisk 1992 Hz i tryl ok. 3,7 kHz (7/s)
  macierz adresowa    ton 759 Hz z harmonicznymi (1518, 2277, 3036 Hz) pulsujący 6,8/s, terkot,
                      na końcu czyste piski 3,2 kHz 11/s urwane nagle
  wybór INTERFACE     jąkająca się sekwencja bloków ok. 100 ms (490/735/980/1470 Hz)
  pisanie tekstu      piski 2,4–3,0 kHz z kliknięciem przy każdej literze, zatrzask ok. 1 kHz na końcu
  klawisze            czysty pisk 2982 Hz z kliknięciem

Ścieżki rozruchu (boot_full.wav, boot_short.wav) powstają z config/boot-timeline.json,
tego samego harmonogramu, którego używa animacja, więc obraz i dźwięk są zsynchronizowane.

Użycie: python tools/build_sounds.py [--out build/sounds]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMELINE = ROOT / "config" / "boot-timeline.json"
RATE = 44100
SEED = 937  # rozkaz specjalny 937
MASTER_PEAK = 0.42

# Szereg harmonicznych przycisku dostępu (zmierzony): numer harmonicznej -> dB.
BUTTON_PARTIALS = {1: -18, 2: 0, 3: -3, 4: -12, 5: -13, 6: -13, 8: -10, 9: -22}
MATRIX_PARTIALS = {1: 0, 2: -5, 3: -7, 4: -9}
TYPING_FREQS = [2438, 2487, 2562, 2605, 2842, 2998]


def rng_for(name: str) -> random.Random:
    return random.Random(f"{SEED}-{name}")


# ─── Harmonogram (wspólny z animacją) ────────────────────────────────────────

def load_timeline(path: Path = TIMELINE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def stage_plan(tl: dict, mode: str) -> list[tuple[dict, int, int]]:
    """[(etap, start_ms, czas_ms)]. Etap 'ready' trwa len(tekst) × charMs + readyHoldMs."""
    plan, t = [], 0
    for st in tl[mode]:
        ms = st.get("ms")
        if st["id"] == "ready":
            ms = len(tl["texts"]["ready"]) * tl["charMs"] + tl["readyHoldMs"]
        plan.append((st, t, ms))
        t += ms
    return plan


def total_ms(tl: dict, mode: str) -> int:
    return sum(ms for _, _, ms in stage_plan(tl, mode))


# ─── Bloki syntezy ───────────────────────────────────────────────────────────

class Track:
    """Ścieżka, na której umieszcza się dźwięki w zadanych chwilach (ms)."""

    def __init__(self, ms: int):
        self.buf = [0.0] * int(RATE * ms / 1000)

    def put(self, at_ms: float, samples: list[float], gain: float = 1.0) -> None:
        start = int(RATE * at_ms / 1000)
        for i, s in enumerate(samples):
            j = start + i
            if 0 <= j < len(self.buf):
                self.buf[j] += s * gain


def n_of(sec: float) -> int:
    return max(1, int(RATE * sec))


def envelope(n: int, attack: float, release: float) -> list[float]:
    a, r = max(1, int(RATE * attack)), max(1, int(RATE * release))
    out = []
    for i in range(n):
        v = 1.0
        if i < a:
            v = i / a
        if i > n - r:
            v = min(v, max(0.0, (n - i) / r))
        out.append(v)
    return out


def harmonic(f0: float, partials: dict[int, float], sec: float, amp: float,
             am_rate: float = 0.0, am_depth: float = 0.0, attack=0.004, release=0.02) -> list[float]:
    n = n_of(sec)
    env = envelope(n, attack, release)
    weights = [(h, 10 ** (db / 20)) for h, db in partials.items()]
    norm = sum(w for _, w in weights)
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(w * math.sin(2 * math.pi * f0 * h * t) for h, w in weights) / norm
        if am_rate:
            s *= 1 - am_depth * (0.5 + 0.5 * math.sin(2 * math.pi * am_rate * t))
        out.append(s * amp * env[i])
    return out


def sine(freq: float, sec: float, amp: float, attack=0.002, release=0.01) -> list[float]:
    n = n_of(sec)
    env = envelope(n, attack, release)
    return [math.sin(2 * math.pi * freq * i / RATE) * amp * env[i] for i in range(n)]


def soft_square(freq: float, sec: float, amp: float, attack=0.002, release=0.01) -> list[float]:
    n = n_of(sec)
    env = envelope(n, attack, release)
    out = []
    for i in range(n):
        x = 2 * math.pi * freq * i / RATE
        out.append((math.sin(x) + math.sin(3 * x) / 3 + math.sin(5 * x) / 5) * 0.8 * amp * env[i])
    return out


def click(sec: float, amp: float, rng: random.Random, decay: float = 600.0, smooth: float = 0.45) -> list[float]:
    out, prev = [], 0.0
    for i in range(n_of(sec)):
        raw = rng.uniform(-1, 1) * math.exp(-decay * i / RATE)
        prev += smooth * (raw - prev)
        out.append(prev * amp)
    return out


def biquad(samples: list[float], kind: str, freq: float, q: float = 0.9) -> list[float]:
    w = 2 * math.pi * freq / RATE
    alpha, cw = math.sin(w) / (2 * q), math.cos(w)
    if kind == "lowpass":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "highpass":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for x in samples:
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def drive(samples: list[float], gain: float) -> list[float]:
    return [math.tanh(s * gain) / math.tanh(gain) for s in samples]


def gated(samples: list[float], rate: float, duty: float, phase: float = 0.0) -> list[float]:
    period = RATE / rate
    ramp = int(RATE * 0.004)
    out = []
    for i, s in enumerate(samples):
        pos = (i + phase * period) % period
        on = period * duty
        if pos < ramp:
            g = pos / ramp
        elif pos < on - ramp:
            g = 1.0
        elif pos < on:
            g = (on - pos) / ramp
        else:
            g = 0.0
        out.append(s * g)
    return out


def normalize(samples: list[float], peak: float) -> list[float]:
    m = max((abs(s) for s in samples), default=0.0) or 1.0
    return [s / m * peak for s in samples]


# ─── Elementy z filmu ────────────────────────────────────────────────────────

def relay(rng: random.Random, amp: float = 0.5) -> list[float]:
    """Pojedynczy trzask przekaźnika/przełącznika: szum w paśmie 2–5 kHz."""
    return biquad(click(rng.uniform(0.008, 0.014), amp, rng, decay=rng.uniform(300, 500), smooth=0.8),
                  "bandpass", rng.uniform(2500, 4000), q=0.8)


def rattle(rng: random.Random, sec: float, rate: float, amp: float) -> list[float]:
    """Terkot przekaźników i głowic: trzaski w nieregularnym rytmie wokół rate/s."""
    t = Track(int(sec * 1000))
    pos = 0.0
    while pos < sec * 1000:
        t.put(pos, relay(rng, rng.uniform(0.5, 1.0)))
        pos += 1000 / rate * rng.uniform(0.7, 1.3)
    return drive([s * amp * 2.5 for s in t.buf], 1.8)


def buzz_burst(rng: random.Random, sec: float, amp: float) -> list[float]:
    """Krótka brzęcząca seria harmonicznych ok. 1 kHz (2–7 kHz) z drżeniem 43 Hz."""
    return harmonic(1000, {2: 0, 3: -3, 4: -6, 5: -8, 6: -10, 7: -12}, sec, amp,
                    am_rate=43, am_depth=0.6, attack=0.002, release=0.01)


def button_tone(sec: float, amp: float) -> list[float]:
    return drive(harmonic(245, BUTTON_PARTIALS, sec, amp, am_rate=43, am_depth=0.35,
                          attack=0.006, release=0.03), 1.5)


def typing_tick(rng: random.Random, amp: float = 0.32) -> list[float]:
    """Litera na ekranie: pisk 2,4–3,0 kHz z suchym kliknięciem."""
    f = rng.choice(TYPING_FREQS)
    beep = soft_square(f, 0.026, 0.55, attack=0.001, release=0.014)
    knock = click(0.006, 0.9, rng, decay=900, smooth=0.6)
    out = [0.0] * max(len(beep), len(knock))
    for i, s in enumerate(beep):
        out[i] += s
    for i, s in enumerate(knock):
        out[i] += s
    return [s * amp for s in out]


def latch(rng: random.Random, amp: float = 0.4) -> list[float]:
    body = biquad(click(0.05, 1.0, rng, decay=170), "bandpass", 1000, q=1.2)
    thump = sine(250, 0.04, 0.5, release=0.03)
    out = [0.0] * len(body)
    for i, s in enumerate(body):
        out[i] = s + (thump[i] if i < len(thump) else 0.0)
    return [s * amp for s in drive(out, 2.0)]


SELECT_BLOCKS = [(490, {1: 0, 2: -4, 3: -8, 4: -10}), (735, {1: 0, 2: -6}), (490, {1: 0, 2: -4, 3: -8}),
                 (980, {1: 0, 1.5: -6}), (490, {1: 0, 2: -4})]


def select_block(k: int, amp: float = 0.35) -> list[float]:
    """Blok jąkającego się buczenia z wyboru INTERFACE 2037 (ok. 85 ms)."""
    f, parts = SELECT_BLOCKS[k % len(SELECT_BLOCKS)]
    return drive(harmonic(f, parts, 0.085, amp, am_rate=43, am_depth=0.3), 1.6)


def stutter(blocks: int, amp: float = 0.35) -> list[float]:
    tr = Track(blocks * 110)
    for k in range(blocks):
        tr.put(k * 110, select_block(k, amp))
    return tr.buf


def low_knock(rng: random.Random, amp: float = 0.5) -> list[float]:
    """Niski, stłumiony trzask przekaźnika (bez wysokiego syku)."""
    body = biquad(click(0.03, 1.0, rng, decay=220, smooth=0.5), "lowpass", 900, q=0.9)
    thump = sine(180, 0.03, 0.6, release=0.02)
    out = [0.0] * len(body)
    for i, s in enumerate(body):
        out[i] = s + (thump[i] if i < len(thump) else 0.0)
    return [s * amp for s in drive(out, 1.8)]


def room_hum(sec: float, amp: float, rng: random.Random) -> list[float]:
    n = n_of(sec)
    noise = biquad([rng.uniform(-1, 1) for _ in range(n)], "lowpass", 500)
    env = envelope(n, 0.3, 0.3)
    out = []
    for i in range(n):
        t = i / RATE
        s = (math.sin(2 * math.pi * 150 * t) + 0.22 * math.sin(2 * math.pi * 300 * t)
             + 0.1 * math.sin(2 * math.pi * 450 * t) + 0.28 * math.sin(2 * math.pi * 65 * t))
        out.append((s / 1.6 + noise[i] * 0.5) * amp * env[i])
    return out


# ─── Ścieżki rozruchu ────────────────────────────────────────────────────────

def boot_track(tl: dict, mode: str) -> list[float]:
    plan = stage_plan(tl, mode)
    total = total_ms(tl, mode)
    tr = Track(total)
    r = rng_for(f"boot-{mode}")
    texts = tl["texts"]

    tr.put(0, room_hum(total / 1000, 0.05, r))

    for st, at, ms in plan:
        sid = st["id"]
        if sid == "access":
            tr.put(at, relay(r, 0.9), 0.6)
            b0 = at + st["buttonAtMs"]
            tr.put(b0, button_tone(st["buttonMs"] / 1000, 0.5))
            tr.put(b0 + st["buttonMs"], relay(r, 0.9), 0.6)
        elif sid == "systems":
            for k, (_, _, kind) in enumerate(texts["checks"]):
                t0 = at + k * st["lineMs"]
                tr.put(t0, relay(r, 0.8), 0.5)
                ts = t0 + st["statusOffsetMs"]
                if kind == "ok":
                    tr.put(ts, relay(r, 1.0), 0.6)
                    tr.put(ts, buzz_burst(r, 0.06, 0.12))
                elif kind == "warn":
                    tr.put(ts, button_tone(0.16, 0.4))
                else:
                    tr.put(ts, drive(gated(harmonic(245, BUTTON_PARTIALS, 0.3, 0.5), 10, 0.6), 1.6))
        elif sid == "room":
            lights = st["lightsMs"]
            tr.put(at, gated(button_tone(lights / 1000, 0.32), 2.8, 0.62))
            tr.put(at, rattle(r, lights / 1000, 18, 0.14))
            pos = at + lights
            while pos < at + ms - 15:
                tr.put(pos, sine(r.uniform(4200, 4800), r.uniform(0.010, 0.015), 0.16, release=0.006))
                pos += 1000 / 10 * r.uniform(0.6, 1.4)
        elif sid == "crt":
            step = 1000 / 13
            k, pos = 0, at
            while pos < at + st["drawMs"]:
                f = 2200 + (k % 8) * 200
                tr.put(pos, soft_square(f, 0.05, 0.14, release=0.015))
                pos += step
                k += 1
            hold = (ms - st["drawMs"]) / 1000
            t0 = at + st["drawMs"]
            tr.put(t0, sine(1992, hold, 0.05, attack=0.02, release=0.03))
            trill = [math.sin(2 * math.pi * (3700 + 200 * (1 if math.sin(2 * math.pi * 7 * i / RATE) > 0 else -1)) * i / RATE)
                     * 0.07 for i in range(n_of(hold))]
            tr.put(t0, [s * e for s, e in zip(trill, envelope(len(trill), 0.01, 0.03))])
        elif sid == "matrix":
            scan = st["tableMs"] / 1000
            tr.put(at, rattle(r, scan, 27, 0.16))
            tr.put(at, gated(drive(harmonic(759, MATRIX_PARTIALS, scan, 0.3), 1.8), 6.8, 0.55))
            pos = at + 60
            while pos < at + st["tableMs"]:
                tr.put(pos, soft_square(r.uniform(2500, 3500), 0.06, 0.09))
                pos += r.uniform(120, 200)
            # Czyste piski potwierdzenia; w filmie urywają się nagle wraz z końcem etapu.
            pos = at + st["tableMs"]
            while pos < at + ms - 30:
                tr.put(pos, sine(3200, 0.04, 0.16, release=0.01))
                pos += 1000 / 11
        elif sid == "select":
            pos, k = at, 0
            while pos < at + ms - 60:
                tr.put(pos, select_block(k))
                pos += 110
                k += 1
        elif sid == "clear":
            burst = biquad([r.uniform(-1, 1) * math.exp(-25 * i / RATE) for i in range(n_of(ms / 1000))],
                           "highpass", 600)
            tr.put(at, [s * 0.35 for s in burst])
        elif sid == "ready":
            text = texts["ready"]
            for i, ch in enumerate(text):
                if ch != " ":
                    tr.put(at + i * tl["charMs"], typing_tick(r))
            tr.put(at + len(text) * tl["charMs"], latch(r, 0.45))

    return normalize(tr.buf, MASTER_PEAK)


# ─── Dźwięki sesji Claude ────────────────────────────────────────────────────

def concat(*parts: list[float]) -> list[float]:
    out: list[float] = []
    for p in parts:
        out.extend(p)
    return out


def build_all(tl: dict | None = None) -> dict[str, list[float]]:
    tl = tl or load_timeline()
    s: dict[str, list[float]] = {
        "boot_full": boot_track(tl, "full"),
        "boot_short": boot_track(tl, "short"),
    }
    # Sesja Claude: niższe brzmienia z animacji (życzenie użytkownika), bez wysokich pisków.
    r = rng_for("inquiry")   # zwrot „Matko”: trzask i krótki ton przycisku dostępu
    s["inquiry"] = concat(low_knock(r), [0.0] * n_of(0.04), button_tone(0.35, 0.38))
    r = rng_for("transmission")   # koniec odpowiedzi: jąkające się buczenie z wyboru INTERFACE
    for name, blocks in (("short", 3), ("medium", 6), ("long", 10)):
        s[f"transmission_{name}"] = concat(stutter(blocks), low_knock(r, 0.45))
    s["tool"] = low_knock(rng_for("tool"), 0.18)
    s["attention"] = button_tone(0.9, 0.38)
    s["error"] = drive(gated(harmonic(245, BUTTON_PARTIALS, 0.3, 0.4), 10, 0.6), 1.6)
    s["alert"] = drive(gated(harmonic(245, BUTTON_PARTIALS, 0.7, 0.4), 7, 0.55), 1.6)
    return {k: normalize(v, min(MASTER_PEAK, max(abs(x) for x in v) or MASTER_PEAK)) for k, v in s.items()}


def write_wav(path: Path, samples: list[float]) -> None:
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in samples)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def build(out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.wav"):   # usuwa dźwięki z poprzednich wersji
        old.unlink()
    paths = []
    for name, samples in build_all().items():
        p = out_dir / f"{name}.wav"
        write_wav(p, samples)
        paths.append(p)
    return paths


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "sounds")
    args = parser.parse_args()
    for p in build(args.out):
        print(p)


if __name__ == "__main__":
    main()
