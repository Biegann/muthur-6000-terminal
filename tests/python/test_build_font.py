import sys
import tempfile
import unittest
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_font  # noqa: E402

POLISH = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"


class BuildFontTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.scale = 1.35
        cls.paths = {s: build_font.build(s, cls.scale, Path(cls.tmp.name)) for s in build_font.SOURCES}
        cls.fonts = {s: TTFont(p) for s, p in cls.paths.items()}
        cls.sources = {s: TTFont(p) for s, p in build_font.SOURCES.items()}

    @classmethod
    def tearDownClass(cls):
        for f in list(cls.fonts.values()) + list(cls.sources.values()):
            f.close()
        cls.tmp.cleanup()

    def test_files_are_written(self):
        for style, path in self.paths.items():
            self.assertTrue(path.is_file(), style)
            self.assertEqual(path.name, f"MUTHURMono-{style}.ttf")

    def test_monospaced_with_scaled_advance(self):
        for style, font in self.fonts.items():
            src_adv = self.sources[style]["hmtx"]["a"][0]
            cmap = font.getBestCmap()
            advances = {font["hmtx"][cmap[ord(c)]][0] for c in "aMiW0ł ąŻ#"}
            self.assertEqual(advances, {round(src_adv * self.scale)}, style)
            self.assertEqual(font["post"].isFixedPitch, 1)

    def test_outlines_scaled_only_horizontally(self):
        for style, font in self.fonts.items():
            src = self.sources[style]
            name = src.getBestCmap()[ord("M")]
            a, b = src["glyf"][name], font["glyf"][name]
            self.assertAlmostEqual(b.xMax, a.xMax * self.scale, delta=2)
            self.assertEqual((b.yMin, b.yMax), (a.yMin, a.yMax))

    def test_polish_letters_present_and_scaled(self):
        for style, font in self.fonts.items():
            cmap = font.getBestCmap()
            glyf = font["glyf"]
            for ch in POLISH:
                self.assertIn(ord(ch), cmap, f"{style}: brak {ch}")
                g = glyf[cmap[ord(ch)]]
                g.recalcBounds(glyf)
                self.assertGreater(g.xMax, 0, f"{style}: pusty glif {ch}")

    def test_renamed_without_source_family_name(self):
        for style, font in self.fonts.items():
            names = font["name"]
            self.assertEqual(names.getDebugName(1), "MUTHUR Mono")
            self.assertEqual(names.getDebugName(2), style)
            self.assertEqual(names.getDebugName(6), f"MUTHURMono-{style}")
            for rec in names.names:
                if rec.nameID in (1, 3, 4, 6, 16, 17):
                    self.assertNotIn("Space Mono", rec.toUnicode())
            # Licencja OFL musi zostać w foncie pochodnym.
            self.assertIn("Open Font License", names.getDebugName(13) or "")

    def test_build_is_reproducible(self):
        with tempfile.TemporaryDirectory() as other:
            for style, path in self.paths.items():
                again = build_font.build(style, self.scale, Path(other))
                self.assertEqual(path.read_bytes(), again.read_bytes(), style)

    def test_hinting_removed(self):
        for font in self.fonts.values():
            for tag in ("fpgm", "prep", "cvt ", "GPOS"):
                self.assertNotIn(tag, font)


if __name__ == "__main__":
    unittest.main()
