"""Generuje motyw Claude Code (plugin/muthur/themes/muthur.json) z config/palette.json.

Użycie: python tools/build_claude_theme.py [--check]
--check: tylko sprawdza, czy zapisany motyw zgadza się z paletą (kod 1, gdy nie).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTE = ROOT / "config" / "palette.json"
THEME = ROOT / "plugin" / "muthur" / "themes" / "muthur.json"


def build_theme(p: dict) -> dict:
    a, s = p["ansi"], p["surfaces"]
    overrides = {
        # Tekst i akcenty
        "claude": p["phosphor"],
        "claudeShimmer": p["phosphorBright"],
        "text": p["phosphor"],
        "inverseText": p["background"],
        "inactive": a["brightBlack"],
        "inactiveShimmer": p["phosphor"],
        "subtle": s["border"],
        "suggestion": p["phosphorBright"],
        "permission": p["amber"],
        "permissionShimmer": a["brightYellow"],
        "remember": a["cyan"],
        # Stany
        "success": p["phosphorBright"],
        "error": p["red"],
        "warning": p["amber"],
        "warningShimmer": a["brightYellow"],
        "merged": a["purple"],
        # Pole promptu i tryby
        "promptBorder": p["phosphorDim"],
        "promptBorderShimmer": p["phosphor"],
        "planMode": a["cyan"],
        "autoAccept": a["brightYellow"],
        "bashBorder": p["amber"],
        "ide": p["phosphorDim"],
        "fastMode": p["amber"],
        "fastModeShimmer": a["brightYellow"],
        "effortUltra": p["amber"],
        # Diffy
        "diffAdded": s["diffAdded"],
        "diffRemoved": s["diffRemoved"],
        "diffAddedDimmed": s["diffAddedDimmed"],
        "diffRemovedDimmed": s["diffRemovedDimmed"],
        "diffAddedWord": s["diffAddedWord"],
        "diffRemovedWord": s["diffRemovedWord"],
        # Tła
        "userMessageBackground": s["userMessage"],
        "userMessageBackgroundHover": s["userMessageHover"],
        "bashMessageBackgroundColor": s["bashMessage"],
        "memoryBackgroundColor": s["memoryMessage"],
        "selectionBg": p["selection"],
        "composerSidebarBackground": s["sidebar"],
        # Licznik użycia i etykiety
        "rate_limit_fill": p["phosphor"],
        "rate_limit_empty": p["phosphorFaint"],
        "briefLabelYou": p["phosphorDim"],
        "briefLabelClaude": p["phosphorBright"],
        # Logo na ekranie powitalnym (tokeny spoza dokumentacji, znalezione w Claude Code 2.1.319)
        "clawd_body": p["phosphor"],
        "clawd_background": p["background"],
        # Kolory subagentów: zieleń, bursztyn i czerwień jak na pokładzie Nostromo
        "red_FOR_SUBAGENTS_ONLY": p["red"],
        "blue_FOR_SUBAGENTS_ONLY": a["brightBlue"],
        "green_FOR_SUBAGENTS_ONLY": p["phosphor"],
        "yellow_FOR_SUBAGENTS_ONLY": p["amber"],
        "purple_FOR_SUBAGENTS_ONLY": a["brightPurple"],
        "orange_FOR_SUBAGENTS_ONLY": s["orange"],
        "pink_FOR_SUBAGENTS_ONLY": s["pink"],
        "cyan_FOR_SUBAGENTS_ONLY": a["cyan"],
    }
    return {"name": "MU/TH/UR 6000", "base": "dark", "overrides": overrides}


def render(theme: dict) -> str:
    return json.dumps(theme, ensure_ascii=False, indent=2) + "\n"


def main(argv: list[str]) -> int:
    palette = json.loads(PALETTE.read_text(encoding="utf-8"))
    text = render(build_theme(palette))
    if "--check" in argv:
        current = THEME.read_text(encoding="utf-8") if THEME.exists() else ""
        # Git z core.autocrlf może zamienić końce linii przy checkoucie.
        if current.replace("\r\n", "\n") != text:
            print(f"{THEME} nie zgadza się z paletą. Uruchom: python tools/build_claude_theme.py")
            return 1
        return 0
    THEME.parent.mkdir(parents=True, exist_ok=True)
    THEME.write_text(text, encoding="utf-8", newline="\n")
    print(THEME)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
