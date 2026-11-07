"""Dodaje BOM UTF-8 do skryptów PowerShella (.ps1/.psm1/.psd1).

Windows PowerShell 5.1 czyta pliki bez BOM jako ANSI, co psuje polskie znaki.
Użycie: python tools/add_bom.py [katalog ...]
"""
import sys
from pathlib import Path

BOM = b"\xef\xbb\xbf"
EXTS = {".ps1", ".psm1", ".psd1"}
SKIP = {".venv", ".git", "vendor", "build"}


def ps_files(root: Path):
    for p in root.rglob("*"):
        if p.suffix.lower() in EXTS and not SKIP.intersection(p.relative_to(root).parts):
            yield p


def main(roots):
    for root in roots:
        for p in ps_files(root):
            data = p.read_bytes()
            if not data.startswith(BOM):
                p.write_bytes(BOM + data)
                print(f"BOM: {p}")


if __name__ == "__main__":
    main([Path(a) for a in sys.argv[1:]] or [Path(__file__).resolve().parent.parent])
