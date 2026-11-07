"""Buduje font MUTHUR Mono: Space Mono (OFL) rozciągnięty w poziomie.

Na ekranach MU/TH/UR 6000 w filmie „Obcy” (1979) tekst był pisany optycznie
rozciągniętym w poziomie krojem z szeryfami. Terminal wymaga fontu o stałej
szerokości znaków, więc bierzemy Space Mono i skalujemy go tylko w osi X.

Użycie:
    python tools/build_font.py [--scale 1.35] [--out build/fonts]
"""
from __future__ import annotations

import argparse
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.ttProgram import Program

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "vendor" / "spacemono"
FAMILY = "MUTHUR Mono"
DEFAULT_SCALE = 1.35
SOURCES = {
    "Regular": VENDOR / "SpaceMono-Regular.ttf",
    "Bold": VENDOR / "SpaceMono-Bold.ttf",
}


def _scale_glyphs(font: TTFont, scale: float) -> None:
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        if glyph.isComposite():
            # Komponenty wskazują na już przeskalowane glify,
            # więc skalujemy tylko ich przesunięcie w poziomie.
            for comp in glyph.components:
                comp.x = round(comp.x * scale)
        elif glyph.numberOfContours > 0:
            coords = glyph.coordinates
            for i, (x, y) in enumerate(coords):
                coords[i] = (round(x * scale), y)
        # Instrukcje hintingu przestają pasować do zmienionych konturów.
        if hasattr(glyph, "program"):
            empty = Program()
            empty.fromBytecode(b"")
            glyph.program = empty
        advance, lsb = hmtx[name]
        hmtx[name] = (round(advance * scale), round(lsb * scale))
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        glyph.recalcBounds(glyf)


def _drop_hinting_and_positioning(font: TTFont) -> None:
    # Hinting nie pasuje do przeskalowanych konturów. GPOS (kotwice znaków
    # diakrytycznych i kerning) ma współrzędne X, a font o stałej szerokości
    # w terminalu go nie potrzebuje: polskie litery są gotowymi glifami.
    for tag in ("fpgm", "prep", "cvt ", "hdmx", "LTSH", "VDMX", "GPOS"):
        if tag in font:
            del font[tag]
    if "gasp" in font:
        # Bez hintingu: wygładzanie na wszystkich rozmiarach.
        font["gasp"].gaspRange = {0xFFFF: 0x000F}
    maxp = font["maxp"]
    for attr in ("maxSizeOfInstructions", "maxFunctionDefs", "maxInstructionDefs",
                 "maxStackElements", "maxTwilightPoints", "maxStorage"):
        if hasattr(maxp, attr):
            setattr(maxp, attr, 0)
    maxp.maxZones = 1


def _rename(font: TTFont, style: str, scale: float) -> None:
    name = font["name"]
    full = f"{FAMILY} {style}" if style != "Regular" else FAMILY
    ps = f"MUTHURMono-{style}"
    note = (f"MUTHUR Mono: font pochodny Space Mono, rozciągnięty w poziomie "
            f"o {round(scale * 100)}%. Hołd dla terminala MU/TH/UR 6000 z filmu „Obcy” (1979).")
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 10):
            name.removeNames(nameID=rec.nameID)
    name.setName(FAMILY, 1, 3, 1, 0x409)
    name.setName(style, 2, 3, 1, 0x409)
    name.setName(f"{ps};muthur-theme", 3, 3, 1, 0x409)
    name.setName(full, 4, 3, 1, 0x409)
    name.setName(ps, 6, 3, 1, 0x409)
    name.setName(note, 10, 3, 1, 0x409)
    font["OS/2"].xAvgCharWidth = round(font["OS/2"].xAvgCharWidth * scale)
    font["post"].isFixedPitch = 1


def build(style: str, scale: float, out_dir: Path) -> Path:
    # recalcTimestamp=False: data modyfikacji zostaje z fontu źródłowego, więc
    # kolejne buildy są identyczne bajt w bajt i instalator nie podmienia fontu bez potrzeby.
    font = TTFont(SOURCES[style], recalcTimestamp=False)
    _scale_glyphs(font, scale)
    _drop_hinting_and_positioning(font)
    _rename(font, style, scale)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"MUTHURMono-{style}.ttf"
    font.save(out)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--scale", type=float, default=DEFAULT_SCALE)
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "fonts")
    args = parser.parse_args()
    for style in SOURCES:
        print(build(style, args.scale, args.out))


if __name__ == "__main__":
    main()
