import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_claude_theme as bct  # noqa: E402

HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
# Tokeny z dokumentacji Claude Code (terminal-config, „Color token reference”).
KNOWN = {
    "claude", "claudeShimmer", "text", "inverseText", "inactive", "inactiveShimmer", "subtle",
    "suggestion", "permission", "permissionShimmer", "remember", "success", "error", "warning",
    "warningShimmer", "merged", "promptBorder", "promptBorderShimmer", "planMode", "autoAccept",
    "bashBorder", "ide", "fastMode", "fastModeShimmer", "effortUltra", "diffAdded", "diffRemoved",
    "diffAddedDimmed", "diffRemovedDimmed", "diffAddedWord", "diffRemovedWord",
    "userMessageBackground", "userMessageBackgroundHover", "bashMessageBackgroundColor",
    "memoryBackgroundColor", "selectionBg", "composerSidebarBackground", "rate_limit_fill",
    "rate_limit_empty", "briefLabelYou", "briefLabelClaude",
    # Spoza dokumentacji: kolory logo na ekranie powitalnym.
    "clawd_body", "clawd_background",
} | {f"{c}_FOR_SUBAGENTS_ONLY" for c in ("red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan")}


class ClaudeThemeTest(unittest.TestCase):
    def setUp(self):
        self.palette = json.loads(bct.PALETTE.read_text(encoding="utf-8"))
        self.theme = bct.build_theme(self.palette)

    def test_committed_theme_matches_palette(self):
        self.assertEqual(bct.main(["--check"]), 0)

    def test_only_documented_tokens_with_hex_values(self):
        overrides = self.theme["overrides"]
        self.assertEqual(set(overrides) - KNOWN, set())
        for token, value in overrides.items():
            self.assertRegex(value, HEX, token)

    def test_core_colors(self):
        o = self.theme["overrides"]
        self.assertEqual(self.theme["base"], "dark")
        self.assertEqual(o["text"], self.palette["phosphor"])
        self.assertEqual(o["error"], self.palette["red"])
        self.assertEqual(o["permission"], self.palette["amber"])


if __name__ == "__main__":
    unittest.main()
