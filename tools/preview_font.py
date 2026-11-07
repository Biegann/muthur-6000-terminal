"""Renderuje podgląd PNG fontu w kolorach terminala Matki (porównanie kilku skal)."""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_font  # noqa: E402

LINES = [
    "INTERFEJS 2037 GOTOWY DO ZAPYTAŃ",
    "ROZKAZ SPECJALNY 937 — ZAŁOGA ZBĘDNA",
    "def zażółć(gęślą: jaźń) -> None:  # 0123456789",
]
BG, FG = (0, 3, 0), (138, 245, 160)


def main(out: Path, scales: list[float]) -> None:
    size = 30
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for s in scales:
            path = build_font.build("Regular", s, Path(tmp) / str(s))
            font = ImageFont.truetype(str(path), size)
            label = ImageFont.truetype(str(path), 16)
            img = Image.new("RGB", (1500, 40 + len(LINES) * 46), BG)
            d = ImageDraw.Draw(img)
            d.text((10, 8), f"skala {s}", font=label, fill=(62, 140, 85))
            for i, line in enumerate(LINES):
                d.text((10, 34 + i * 46), line, font=font, fill=FG)
            rows.append(img)
    sheet = Image.new("RGB", (1500, sum(r.height for r in rows)), BG)
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main(Path(sys.argv[1]), [float(a) for a in sys.argv[2:]] or [1.0, 1.3, 1.5])
