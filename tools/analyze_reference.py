"""Analiza nagrania referencyjnego (sceny z MATKĄ) do strojenia syntezy dźwięków.

Nagranie leży w reference/audio (poza repozytorium) i nie trafia do motywu.
Służy tylko do pomiarów: spektrogramy, częstotliwości szczytowe, tempo impulsów.

Użycie:
  python tools/analyze_reference.py spectrogram PLIK.wav START END OUT.png [--fmax 12000]
  python tools/analyze_reference.py peaks PLIK.wav START END [--n 8]
  python tools/analyze_reference.py rate PLIK.wav START END [--band 1000 4000]
  python tools/analyze_reference.py profile PLIK.wav START END [--step 0.25]
"""
from __future__ import annotations

import argparse
import wave

import numpy as np
from PIL import Image, ImageDraw


def load(path: str, start: float, end: float) -> tuple[np.ndarray, int]:
    with wave.open(path, "rb") as w:
        rate, ch, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        w.setpos(int(start * rate))
        raw = w.readframes(int((end - start) * rate))
    data = np.frombuffer(raw, dtype=np.int16 if width == 2 else np.int32).astype(np.float64)
    data = data.reshape(-1, ch).mean(axis=1) / (32768.0 if width == 2 else 2 ** 31)
    return data, rate


def stft(x: np.ndarray, n: int = 2048, hop: int = 256) -> np.ndarray:
    win = np.hanning(n)
    frames = [x[i:i + n] * win for i in range(0, len(x) - n, hop)]
    return np.abs(np.fft.rfft(np.array(frames), axis=1)).T  # [freq, time]


def bandpass_env(x: np.ndarray, rate: int, lo: float, hi: float, hop: int = 128) -> np.ndarray:
    spec = stft(x, 1024, hop)
    freqs = np.fft.rfftfreq(1024, 1 / rate)
    band = spec[(freqs >= lo) & (freqs <= hi)]
    return band.sum(axis=0)


def cmd_spectrogram(a) -> None:
    x, rate = load(a.file, a.start, a.end)
    n, hop = 2048, 256
    spec = stft(x, n, hop)
    freqs = np.fft.rfftfreq(n, 1 / rate)
    db = 20 * np.log10(spec + 1e-9)
    db = np.clip((db - db.max() + 80) / 80, 0, 1)
    # Logarytmiczna oś częstotliwości 40 Hz .. fmax
    h, fmin = 420, 40.0
    rows = np.geomspace(fmin, a.fmax, h)[::-1]
    idx = np.clip(np.searchsorted(freqs, rows), 0, len(freqs) - 1)
    img = (db[idx] * 255).astype(np.uint8)
    width = min(1800, img.shape[1])
    pic = Image.fromarray(img).resize((width, h))
    pic = pic.convert("RGB")
    canvas = Image.new("RGB", (width + 60, h + 30), (0, 0, 0))
    canvas.paste(pic, (60, 0))
    d = ImageDraw.Draw(canvas)
    for f in (60, 100, 200, 400, 800, 1000, 2000, 3000, 5000, 8000, 12000):
        if fmin <= f <= a.fmax:
            y = int(h - 1 - (np.log(f / fmin) / np.log(a.fmax / fmin)) * (h - 1))
            d.line([(55, y), (width + 60, y)], fill=(0, 90, 0))
            d.text((2, y - 6), f"{f}", fill=(0, 255, 0))
    dur = a.end - a.start
    for s in np.arange(0, dur + 1e-9, 1.0 if dur <= 30 else 5.0):
        xpix = 60 + int(s / dur * (width - 1))
        d.line([(xpix, 0), (xpix, h)], fill=(90, 0, 0))
        d.text((xpix + 2, h + 8), f"{a.start + s:.0f}s", fill=(255, 120, 120))
    canvas.save(a.out)
    print(a.out)


def cmd_peaks(a) -> None:
    x, rate = load(a.file, a.start, a.end)
    spec = stft(x, 8192, 2048).mean(axis=1)
    freqs = np.fft.rfftfreq(8192, 1 / rate)
    spec[freqs < 30] = 0
    peaks = []
    for i in np.argsort(spec)[::-1]:
        if all(abs(freqs[i] - p) > 40 for p, _ in peaks):
            peaks.append((freqs[i], spec[i]))
        if len(peaks) >= a.n:
            break
    top = peaks[0][1]
    for f, v in sorted(peaks):
        print(f"{f:8.1f} Hz  {20 * np.log10(v / top):6.1f} dB")
    centroid = (spec * freqs).sum() / spec.sum()
    flat = np.exp(np.mean(np.log(spec[freqs > 100] + 1e-12))) / np.mean(spec[freqs > 100])
    print(f"środek ciężkości widma: {centroid:.0f} Hz, płaskość (szumowość 0..1): {flat:.3f}")
    print(f"RMS: {20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12):.1f} dBFS")


def cmd_rate(a) -> None:
    x, rate = load(a.file, a.start, a.end)
    hop = 128
    env = bandpass_env(x, rate, a.band[0], a.band[1], hop)
    env = env - np.convolve(env, np.ones(31) / 31, mode="same")   # usuwa wolne zmiany
    env = np.maximum(env, 0)
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    fps = rate / hop
    lo, hi = int(fps / 40), int(fps / 2)   # tempo 2..40 impulsów/s
    lag = lo + int(np.argmax(ac[lo:hi]))
    print(f"tempo impulsów w paśmie {a.band[0]}-{a.band[1]} Hz: {fps / lag:.1f} /s (okres {1000 * lag / fps:.0f} ms)")


def cmd_profile(a) -> None:
    """Profil w czasie: głośność, środek widma i szumowość co --step s."""
    x, rate = load(a.file, a.start, a.end)
    step = int(a.step * rate)
    for i in range(0, len(x) - step, step):
        seg = x[i:i + step]
        sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
        fr = np.fft.rfftfreq(len(seg), 1 / rate)
        rms = 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-12)
        cen = (sp * fr).sum() / (sp.sum() + 1e-12)
        mask = fr > 100
        flat = np.exp(np.mean(np.log(sp[mask] + 1e-12))) / (np.mean(sp[mask]) + 1e-12)
        low = 20 * np.log10(sp[(fr > 40) & (fr < 120)].sum() / (sp.sum() + 1e-12) + 1e-12)
        pk = fr[mask][np.argmax(sp[mask])]
        print(f"{a.start + i / rate:7.2f}s  RMS {rms:6.1f}  szczyt {pk:6.0f} Hz  środek {cen:6.0f} Hz  szum {flat:.2f}  udział 40-120Hz {low:6.1f} dB")


def main() -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("spectrogram", "peaks", "rate", "profile"):
        s = sub.add_parser(name)
        s.add_argument("file")
        s.add_argument("start", type=float)
        s.add_argument("end", type=float)
        if name == "spectrogram":
            s.add_argument("out")
            s.add_argument("--fmax", type=float, default=12000)
        if name == "peaks":
            s.add_argument("--n", type=int, default=8)
        if name == "rate":
            s.add_argument("--band", type=float, nargs=2, default=[1000, 4000])
        if name == "profile":
            s.add_argument("--step", type=float, default=0.25)
    a = p.parse_args()
    {"spectrogram": cmd_spectrogram, "peaks": cmd_peaks, "rate": cmd_rate, "profile": cmd_profile}[a.cmd](a)


if __name__ == "__main__":
    main()
