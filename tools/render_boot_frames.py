"""Renderuje klatki animacji rozruchu do PNG (podgląd bez prawdziwego terminala).

Wejście: JSON z zapisami animacji [{t: ms, s: tekst z sekwencjami ANSI}, ...]
(nagrany atrapą konsoli z Invoke-MuthurBoot). Emulator terminala pyte odtwarza
ekran w zadanych chwilach, a PIL rysuje go fontem MUTHUR Mono.

Użycie: python tools/render_boot_frames.py zapisy.json OUT_DIR T1 T2 ... [--cols 100 --rows 30]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pyte
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "build" / "fonts" / "MUTHURMono-Regular.ttf"


def color(c: str, default: tuple) -> tuple:
    if c in (None, "default"):
        return default
    if len(c) == 6:
        try:
            return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
        except ValueError:
            pass
    named = {"green": (56, 210, 150), "white": (220, 220, 220), "black": (0, 0, 0)}
    return named.get(c, default)


def render(screen: pyte.Screen, out: Path, size: int = 16) -> None:
    font = ImageFont.truetype(str(FONT), size)
    cw = int(font.getlength("M"))
    ch = int(size * 1.35)
    img = Image.new("RGB", (cw * screen.columns + 20, ch * screen.lines + 20), (8, 12, 10))
    d = ImageDraw.Draw(img)
    for y in range(screen.lines):
        line = screen.buffer[y]
        for x in range(screen.columns):
            cell = line[x]
            if cell.data == " " and not cell.underscore:
                continue
            fg = color(cell.fg, (56, 210, 150))
            px, py = 10 + x * cw, 10 + y * ch
            d.text((px, py), cell.data, font=font, fill=fg)
            if cell.underscore:
                d.line([(px, py + ch - 3), (px + cw, py + ch - 3)], fill=(244, 255, 246), width=2)
    img.save(out)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("writes")
    p.add_argument("out", type=Path)
    p.add_argument("times", type=int, nargs="+")
    p.add_argument("--cols", type=int, default=100)
    p.add_argument("--rows", type=int, default=30)
    a = p.parse_args()
    writes = json.loads(Path(a.writes).read_text(encoding="utf-8"))
    a.out.mkdir(parents=True, exist_ok=True)
    screen = pyte.Screen(a.cols, a.rows)
    stream = pyte.Stream(screen)
    i = 0
    for t in sorted(a.times):
        while i < len(writes) and writes[i]["t"] <= t:
            stream.feed(writes[i]["s"])
            i += 1
        out = a.out / f"frame_{t:05d}.png"
        render(screen, out)
        print(out)


if __name__ == "__main__":
    main()
