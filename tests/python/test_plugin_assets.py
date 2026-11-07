"""Plugin z marketplace'u nie przechodzi przez install.ps1, więc musi mieć w sobie
dźwięki i odtwarzacz, a marketplace musi wskazywać właściwy katalog pluginu."""
import hashlib
import json
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PLUGIN = REPO / 'plugin' / 'muthur'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PluginAssetsTest(unittest.TestCase):
    def test_every_cue_used_by_the_plugin_has_a_sound(self):
        hooks = json.loads((PLUGIN / 'hooks' / 'hooks.json').read_text(encoding='utf-8'))
        cues = set()
        for entries in hooks['hooks'].values():
            for entry in entries:
                for hook in entry['hooks']:
                    if hook['command'].endswith('muthur-play.exe'):
                        cues.update(hook['args'])
        self.assertIn('stop', cues)
        # „stop” odtwarzacz zamienia na transmisję zależną od długości odpowiedzi.
        cues.discard('stop')
        cues.update({'transmission_short', 'transmission_medium', 'transmission_long'})
        submit = (PLUGIN / 'scripts' / 'prompt-submit.ps1').read_text(encoding='utf-8-sig')
        cues.update(re.findall(r"-ArgumentList '([a-z_]+)'", submit))
        self.assertIn('inquiry', cues)
        missing = sorted(c for c in cues if not (PLUGIN / 'sounds' / f'{c}.wav').is_file())
        self.assertEqual(missing, [], 'uruchom tools/stage_plugin_assets.ps1')

    def test_player_is_inside_the_plugin(self):
        self.assertTrue((PLUGIN / 'player' / 'muthur-play.exe').is_file(), 'uruchom tools/stage_plugin_assets.ps1')

    def test_plugin_sounds_match_the_build(self):
        build = REPO / 'build' / 'sounds'
        if not build.is_dir():
            self.skipTest('brak build/sounds (dźwięki niezbudowane)')
        built = {p.name: digest(p) for p in build.glob('*.wav')}
        staged = {p.name: digest(p) for p in (PLUGIN / 'sounds').glob('*.wav')}
        self.assertEqual(staged, built, 'dźwięki w pluginie są nieaktualne: uruchom tools/stage_plugin_assets.ps1')

    def test_marketplace_lists_the_plugin(self):
        market = json.loads((REPO / '.claude-plugin' / 'marketplace.json').read_text(encoding='utf-8'))
        [entry] = market['plugins']
        manifest = json.loads((REPO / entry['source'] / '.claude-plugin' / 'plugin.json').read_text(encoding='utf-8'))
        self.assertEqual(entry['name'], manifest['name'])


if __name__ == '__main__':
    unittest.main()
