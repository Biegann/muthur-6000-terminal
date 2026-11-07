import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "plugin" / "muthur" / "hooks" / "register.tsx"
PALETTE = ROOT / "config" / "palette.json"


class ModColorsTest(unittest.TestCase):
    """Mod nie czyta plików, więc ma kolory wpisane na stałe; muszą się zgadzać z paletą."""

    def test_mod_colors_match_palette(self):
        palette = json.loads(PALETTE.read_text(encoding="utf-8"))
        source = MOD.read_text(encoding="utf-8")
        block = re.search(r"export const COLORS = \{(.*?)\} as const", source, re.S)
        self.assertIsNotNone(block, "brak COLORS w register.tsx")
        colors = dict(re.findall(r"(\w+): '(#[0-9A-Fa-f]{6})'", block.group(1)))
        self.assertTrue(colors)
        for name, value in colors.items():
            self.assertEqual(value.upper(), palette[name].upper(), name)


if __name__ == "__main__":
    unittest.main()
