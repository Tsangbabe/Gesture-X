"""Flashlight scope/byte contracts; not native, UIKit or handset proof.

The local pre-freeze gate compares all 26 restorations with independent
``git show 925df18141606b75f71c77ddd998ad2baa237efe:PATH`` bytes. These tests
must also run in a candidate-only checkout, with no history or subprocesses.
"""
import hashlib
import importlib
import importlib.util
import unittest
from pathlib import Path

import system_mute_baseline as system_mute

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '925df18141606b75f71c77ddd998ad2baa237efe'
CHANGED = frozenset({
    'Makefile', 'Preferences/Resources/Info.plist',
    'Preferences/Resources/SettingsReference.json', 'Preferences/SettingsController.swift',
    'Shared/Preferences.swift', 'Sources/HomeDoubleTap.swift', 'control',
})
ADDED = 'Sources/FlashlightAction.swift'

# Independently frozen from the accepted commit, not from candidate manifests.
HISTORICAL_HELPERS = {
    'Tests/app_switcher_baseline.json': 'f98063b2e23d3a30232c582e962b17f15dbbebe550db4cbfa890574faa1427a4',
    'Tests/app_switcher_baseline.py': '9ee7a0f038f7668531057ef33900c3211b2b90f6a78daa9d94ac01f580f2e85f',
    'Tests/control_center_baseline.json': 'b0e07cd11a98e24f46647ed42201999d287255d8792b1046423b817c8b958b0b',
    'Tests/control_center_baseline.py': '194554a545803b7d7814356be15208d7075b9fd4a0b186f6dbd775964716f1f5',
    'Tests/media_play_pause_baseline.json': 'aedf16740ddc70aecc2d742321966b8c75676c02d88d671cb9de2abb7540164b',
    'Tests/media_play_pause_baseline.py': '52957f9e5313cdbbbb673bab8e598e7aa9c803c8b63b578f12a1e1f79483f4c9',
    'Tests/media_tracks_baseline.json': 'aca11fe24775cb5704bc2a17e48e866cf80d9f403b2ab3e442a34019f3fa1fb8',
    'Tests/media_tracks_baseline.py': 'd980fbf63d3cb7b356f780af3f15faf004623428e70c41afeddcc57a89be1ece',
    'Tests/notification_center_baseline.json': '8dd0e00f7f19ebca9086311ae068b1c886f6b343a009fefd6b8a9c8b8248084e',
    'Tests/notification_center_baseline.py': 'cee933f345fd01d3079e3e7153200335f2c284e1e35b2c53ed0d674e84c53c10',
    'Tests/open_app_baseline.json': 'ea610b08ece737450fe2ee005aecc65bec6ebb753eaeb97b9ec423cd384a8555',
    'Tests/open_app_baseline.py': '4b51c75d136ca27730d27feacef66c1efc5c266572715f926349176d5653adcb',
    'Tests/screenshot_baseline.json': 'e75ff66f8b62bdef53d7e0bf102657c39ee0c30ead287efe25fae0351b71d5b1',
    'Tests/screenshot_baseline.py': '3f175e5ad1f9f2e5c79e4e3e09503f77801a37fb10ed328665d86452c4a6cc55',
    'Tests/settings_hierarchy_baseline.json': '701c83c22c813074ac47d65d7246f7e1c898b1648d09282c7c2c044cf5ce2c3f',
    'Tests/settings_hierarchy_baseline.py': '9708dfebfd134089adcae4999258edba3ef4b988e6e22249d267de471143e355',
    'Tests/settings_layout_baseline.json': 'aac85e23975eb527f466534d7f074ec64197dd2fcaff2cca214edbb49bf0b73a',
}
LAYOUT_INVERSE_SHA256 = 'c54f823bae5caff253e5c44b17d750302036ac5be2e80e8631ae078f282518c7'
FROZEN_MAP_SHA256 = '360fba1a23059c1a0e3fc05540c3c0ede5a6140cfbbe9d965f3b2472dd8cc0e3'



def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def candidate_mutants(text, edits):
    """Return named byte mutations, with each hunk exercised independently."""
    mutants = [('unrelated', text + '\n// unrelated drift\n'),
               ('crlf', text.replace('\n', '\r\n')),
               ('mixed-crlf', text.replace('\n', '\r\n', 1)),
               ('single-byte', ('X' if text[0] != 'X' else 'Y') + text[1:]),
               ('truncated', text[:-1])]
    for index, edit in enumerate(edits):
        mutants.extend([
            (f'missing-{index}', text.replace(edit['after'], '', 1)),
            (f'duplicate-{index}', text + edit['after']),
            (f'indented-{index}', text.replace(edit['after'], ' ' + edit['after'], 1)),
        ])
    if len(edits) > 1:
        assert '__FLASHLIGHT_SWAP__' not in text
        mutants.append(('out-of-order', text.replace(edits[0]['after'], '__FLASHLIGHT_SWAP__', 1)
                        .replace(edits[-1]['after'], edits[0]['after'], 1)
                        .replace('__FLASHLIGHT_SWAP__', edits[-1]['after'], 1)))
    return mutants


class FlashlightBaselineContracts(unittest.TestCase):
    def helper(self):
        self.assertIsNotNone(importlib.util.find_spec('flashlight_baseline'),
                             'Missing exact flashlight inverse')
        return importlib.import_module('flashlight_baseline')

    def test_exact_inverse_restores_all_26_inherited_production_inputs(self):
        helper = self.helper()
        fixture = helper.FIXTURE
        self.assertEqual(fixture['baseline'], BASELINE)
        self.assertEqual(len(fixture['frozen']), 26)
        self.assertEqual(set(fixture['hunks']), CHANGED)
        self.assertNotIn(ADDED, fixture['frozen'], 'Do not fabricate an absent predecessor file')
        for path, frozen in fixture['frozen'].items():
            with self.subTest(path=path):
                text = system_mute.accepted_source(path)
                self.assertEqual(digest(helper.invert_flashlight(path, text)), frozen)
                self.assertEqual(system_mute.accepted_flashlight_source(path), helper.invert_flashlight(path, text))

    def test_added_provider_is_digest_protected_without_a_fabricated_before_file(self):
        helper = self.helper()
        text = (ROOT / ADDED).read_bytes().decode('utf-8')
        self.assertEqual(helper.FIXTURE['candidate_added_sha256'], {
            ADDED: '6991354a10287c9e7dead5d27cc9654f3e8505f12cc51cc4d06280b2c8eadec7',
        })
        self.assertEqual(helper.invert_flashlight(ADDED, text), text)
        body_lines = text.splitlines(keepends=True)
        body_lines[-3], body_lines[-2] = body_lines[-2], body_lines[-3]
        for mutant in (text[:-1], text + text, text + '// drift\n',
                       text.replace('\n', '\r\n'), text.replace('return true', 'return false'),
                       ''.join(body_lines)):
            self.assertNotEqual(mutant, text)
            with self.subTest(mutant=digest(mutant)), self.assertRaises(AssertionError):
                helper.invert_flashlight(ADDED, mutant)

    def test_manifest_has_a_closed_baseline_and_exact_key_sets(self):
        import copy
        from unittest import mock
        helper = self.helper()
        for key in ('baseline', 'frozen', 'hunks', 'candidate_added_sha256'):
            for operation in ('missing', 'extra'):
                fixture = copy.deepcopy(helper.FIXTURE)
                if key == 'baseline':
                    if operation == 'missing':
                        del fixture[key]
                    else:
                        fixture[key] = '0' * 40
                elif operation == 'missing':
                    del fixture[key][next(iter(fixture[key]))]
                else:
                    fixture[key]['Sources/Unexpected.swift'] = 'not authorized'
                with self.subTest(key=key, operation=operation), mock.patch.object(helper, 'FIXTURE', fixture):
                    with self.assertRaises(AssertionError):
                        helper.invert_flashlight('Shared/Preferences.swift', system_mute.accepted_source('Shared/Preferences.swift'))
        for mutation in ('count', 'empty-before', 'empty-after', 'same', 'empty-hunks', 'extra-field'):
            fixture = copy.deepcopy(helper.FIXTURE)
            edit = fixture['hunks']['Shared/Preferences.swift'][0]
            if mutation == 'count':
                edit['count'] = 2
            elif mutation == 'empty-hunks':
                fixture['hunks']['Shared/Preferences.swift'] = []
            elif mutation == 'extra-field':
                edit['unexpected'] = True
            elif mutation == 'same':
                edit['before'] = edit['after']
            else:
                edit[mutation.removeprefix('empty-')] = ''
            with self.subTest(mutation=mutation), mock.patch.object(helper, 'FIXTURE', fixture):
                with self.assertRaises(AssertionError):
                    helper.invert_flashlight('Shared/Preferences.swift', system_mute.accepted_source('Shared/Preferences.swift'))

    def test_unlisted_paths_are_identity_not_path_aliases(self):
        helper = self.helper()
        text = 'unrelated source\r\n'
        for path in ('Unexpected.swift', '../Shared/Preferences.swift',
                     '/Shared/Preferences.swift', 'Shared/Preferences.swift.bak'):
            with self.subTest(path=path):
                self.assertIs(helper.invert_flashlight(path, text), text)

    def test_explicit_read_composition_runs_newest_to_oldest_without_changing_defaults(self):
        import inspect
        from media_tracks_baseline import FIXTURE as tracks, invert_media_tracks
        from media_play_pause_baseline import FIXTURE as media, invert_media_play_pause
        from settings_layout_baseline import FIXTURE as layout, accepted_source, invert_settings_layout
        helper = self.helper()
        self.assertTrue(callable(getattr(helper, 'accepted_media_tracks_source', None)),
                        'Missing explicit flashlight -> tracks read boundary')
        flag = inspect.signature(accepted_source).parameters.get('flashlight')
        self.assertIsNotNone(flag, 'Missing explicit default-false flashlight restoration')
        self.assertIs(flag.default, False)
        path = 'Preferences/SettingsController.swift'
        current = system_mute.accepted_source(path)
        import media_tracks_baseline
        from unittest import mock
        # Default-rejection probes must see the actual flashlight stage, not
        # fail early because an unrelated newer system-mute hunk remains.
        with mock.patch.object(media_tracks_baseline, 'ROOT') as root:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_bytes.return_value = current.encode('utf-8')
            with self.assertRaisesRegex(AssertionError, 'track'):
                media_tracks_baseline.accepted_source(path)
        for inverse in (invert_media_tracks, invert_media_play_pause, invert_settings_layout):
            with self.subTest(inverse=inverse.__name__), self.assertRaises(AssertionError):
                inverse(path, current)
        with mock.patch('settings_layout_baseline.ROOT') as root:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_bytes.return_value = current.encode('utf-8')
            for flags in ({}, {'media_tracks': True}, {'media_play_pause': True, 'media_tracks': True}):
                with self.subTest(flags=flags), self.assertRaises(AssertionError):
                    accepted_source(path, **flags)
        for relative in helper.FIXTURE['frozen']:
            with self.subTest(relative=relative):
                before_tracks = system_mute.accepted_media_tracks_source(relative)
                self.assertEqual(digest(before_tracks), tracks['frozen'][relative])
                before_media = invert_media_play_pause(relative, before_tracks)
                if relative in media['frozen']:
                    self.assertEqual(digest(before_media), media['frozen'][relative])
                restored = system_mute.accepted_layout_source(relative, flashlight=True, media_tracks=True, media_play_pause=True)
                self.assertEqual(restored, invert_settings_layout(relative, before_media))
                if relative in layout['frozen']:
                    self.assertEqual(digest(restored), layout['frozen'][relative])

    def test_all_historical_outer_read_callers_explicitly_opt_in(self):
        import ast
        self.helper()
        calls = 0
        for file in sorted((ROOT / 'Tests').glob('test_*.py')):
            if file.name == 'test_flashlight_baseline.py':
                continue
            tree = ast.parse(file.read_bytes().decode('utf-8'))
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.module == 'media_tracks_baseline':
                    self.assertNotIn('accepted_source', [alias.name for alias in node.names],
                                     file.name + ': direct latest-stage source read bypasses flashlight')
                if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):
                    continue
                if node.func.id not in ('accepted_source', 'accepted_layout_source'):
                    continue
                flags = {k.arg: k.value.value for k in node.keywords if isinstance(k.value, ast.Constant)}
                if flags.get('media_play_pause') is True and flags.get('media_tracks') is True:
                    calls += 1
                    self.assertIs(flags.get('flashlight'), True, (file.name, node.lineno))
        self.assertEqual(calls, 27, 'Reconcile the full historical source-reader inventory')


    def test_all_26_byte_mutations_fail_without_history_and_leave_sources_untouched(self):
        from unittest import mock
        import json
        helper = self.helper()
        self.assertEqual(hashlib.sha256(json.dumps(helper.FIXTURE['frozen'], sort_keys=True).encode()).hexdigest(),
                         FROZEN_MAP_SHA256)
        originals = {path: (ROOT / path).read_bytes() for path in helper.FIXTURE['frozen']}
        rejected = 0
        # These are also the subprocess entry points used by the independent
        # local pre-freeze gate. None may be used by candidate-only contracts.
        with mock.patch('subprocess.run', side_effect=AssertionError('Git/history unavailable')), \
             mock.patch('subprocess.check_output', side_effect=AssertionError('Git/history unavailable')):
            for path, raw in originals.items():
                text = system_mute.accepted_source(path)
                restored = system_mute.accepted_flashlight_source(path)
                self.assertEqual(digest(restored), helper.FIXTURE['frozen'][path])
                for kind, mutant in candidate_mutants(text, helper.FIXTURE['hunks'].get(path, [])):
                    self.assertNotEqual(mutant, text)
                    with self.subTest(path=path, mutation=kind), self.assertRaises(AssertionError):
                        helper.invert_flashlight(path, mutant)
                    rejected += 1
        self.assertEqual(rejected, 162, 'Reconcile exact source-mutation coverage')
        for path, raw in originals.items():
            self.assertEqual((ROOT / path).read_bytes(), raw, path)

    def test_all_hunks_have_unique_complete_before_and_after_lines_in_both_orders(self):
        helper = self.helper()
        self.assertEqual(sum(len(edits) for edits in helper.FIXTURE['hunks'].values()), 10)
        for path, edits in helper.FIXTURE['hunks'].items():
            current = system_mute.accepted_source(path)
            before = helper.invert_flashlight(path, current)
            for side, text in (('after', current), ('before', before)):
                end = -1
                for edit in edits:
                    with self.subTest(path=path, side=side):
                        self.assertEqual(edit['count'], 1)
                        starts = helper._line_starts(text, edit[side])
                        self.assertEqual(len(starts), 1)
                        self.assertGreaterEqual(starts[0], end)
                        end = starts[0] + len(edit[side].splitlines(keepends=True))
            # Also replay the forward delta, independently of inverse order.
            for edit in reversed(edits):
                self.assertEqual(before.count(edit['before']), 1)
                before = before.replace(edit['before'], edit['after'], 1)
            self.assertEqual(before, current)

    def test_all_17_historical_helpers_and_the_layout_inverse_are_byte_frozen(self):
        import ast
        self.assertEqual(len(HISTORICAL_HELPERS), 17)
        for path, frozen in HISTORICAL_HELPERS.items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), frozen)
        source = (ROOT / 'Tests/settings_layout_baseline.py').read_bytes().decode('utf-8')
        body = next(n for n in ast.parse(source).body
                    if isinstance(n, ast.FunctionDef) and n.name == 'invert_settings_layout')
        self.assertEqual(digest(ast.get_source_segment(source, body)), LAYOUT_INVERSE_SHA256)

    def test_original_loaders_lock_private_api_hook_and_icon_inputs_never_changed(self):
        helper = self.helper()
        untouched = set(helper.FIXTURE['frozen']) - CHANGED
        self.assertEqual(len(untouched), 19)
        self.assertTrue({'Sources/MediaPlayPauseAction.swift', 'Sources/LockAction.swift',
                         'Sources/PrivateAPI.swift', 'Sources/NativeHook.swift', 'Sources/Bootstrap.swift',
                         'Preferences/ApplicationIcons.swift',
                         'layout/Library/PreferenceLoader/Preferences/TapLock.plist'} <= untouched)
        for path in untouched:
            text = system_mute.accepted_source(path)
            self.assertEqual(digest(text), helper.FIXTURE['frozen'][path], path)
            self.assertEqual(helper.invert_flashlight(path, text), text)

    def test_read_boundary_preserves_raw_newlines_and_rejects_missing_files(self):
        from unittest import mock
        helper = self.helper()
        path = 'Shared/Preferences.swift'
        raw = system_mute.accepted_source(path).encode('utf-8')
        with mock.patch.object(helper, 'ROOT') as root:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_bytes.return_value = raw
            self.assertEqual(digest(helper.accepted_source(path)), helper.FIXTURE['frozen'][path])
            file.read_bytes.assert_called_once_with()
            file.read_text.assert_not_called()
            file.read_bytes.return_value = raw.replace(b'\n', b'\r\n')
            with self.assertRaises(AssertionError):
                helper.accepted_source(path)
            file.is_file.return_value = False
            with self.assertRaisesRegex(AssertionError, 'Missing implementation'):
                helper.accepted_source(path)


if __name__ == '__main__':
    unittest.main(verbosity=2)
