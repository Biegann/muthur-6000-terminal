import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import add_bom  # noqa: E402


class PowerShellEncodingTest(unittest.TestCase):
    def test_every_powershell_file_has_utf8_bom(self):
        files = list(add_bom.ps_files(ROOT))
        self.assertTrue(files, "nie znaleziono skryptów PowerShella")
        missing = [str(p.relative_to(ROOT)) for p in files if not p.read_bytes().startswith(add_bom.BOM)]
        self.assertEqual(missing, [], "Uruchom: python tools/add_bom.py")


if __name__ == "__main__":
    unittest.main()
