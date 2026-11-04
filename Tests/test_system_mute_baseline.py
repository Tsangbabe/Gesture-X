"""Exact system-mute inverse and explicit historical composition contracts."""
import copy
import hashlib
import importlib
import importlib.util
import json
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '0cc50fbd3e82c336f89394f80cb298aa150a1c70'
MAP_SHA = '94412089e3957967dddc98c7a94d7d996be5432c1725e5ea5cc41486eb7a67f5'
ADDED = 'Sources/SystemMuteAction.swift'
ADDED_SHA = 'b10b9b5499a7bfa31ba698efb6e13a20d1220002ad78507213bde49223f75460'
# Independently frozen from real baseline Git bytes, never regenerated at runtime.
HISTORICAL_INPUT_SHA256 = {'Tests/app_switcher_baseline.json': 'f98063b2e23d3a30232c582e962b17f15dbbebe550db4cbfa890574faa1427a4',
 'Tests/app_switcher_baseline.py': '9ee7a0f038f7668531057ef33900c3211b2b90f6a78daa9d94ac01f580f2e85f',
 'Tests/control_center_baseline.json': 'b0e07cd11a98e24f46647ed42201999d287255d8792b1046423b817c8b958b0b',
 'Tests/control_center_baseline.py': '194554a545803b7d7814356be15208d7075b9fd4a0b186f6dbd775964716f1f5',
 'Tests/flashlight_baseline.json': 'a527237ba974b4f038733cbd970171e6144808dca8047105bcfff2eb065acdae',
 'Tests/flashlight_baseline.py': '897348f8385e14bd6d023a69d4990b9b585c32f942b4ca7b9142742faacc93aa',
 'Tests/media_play_pause_baseline.json': 'aedf16740ddc70aecc2d742321966b8c75676c02d88d671cb9de2abb7540164b',
 'Tests/media_play_pause_baseline.py': '52957f9e5313cdbbbb673bab8e598e7aa9c803c8b63b578f12a1e1f79483f4c9',
 'Tests/media_tracks_baseline.json': 'aca11fe24775cb5704bc2a17e48e866cf80d9f403b2ab3e442a34019f3fa1fb8',
 'Tests/media_tracks_baseline.py': 'd980fbf63d3cb7b356f780af3f15faf004623428e70c41afeddcc57a89be1ece',
 'Tests/notification_center_baseline.json': '8dd0e00f7f19ebca9086311ae068b1c886f6b343a009fefd6b8a9c8b8248084e',
 'Tests/notification_center_baseline.py': 'cee933f345fd01d3079e3e7153200335f2c284e1e35b2c53ed0d674e84c53c10',
 'Tests/open_app_baseline.json': 'ea610b08ece737450fe2ee005aecc65bec6ebb753eaeb97b9ec423cd384a8555',
 'Tests/open_app_baseline.py': '4b51c75d136ca27730d27feacef66c1efc5c266572715f926349176d5653adcb',
 'Tests/reference_settings_oracle.json': 'a0f639ae24ece250a155ee2f88dcb3bc109c56501a05ae2f5f0a366ac4b82fd8',
 'Tests/screenshot_baseline.json': 'e75ff66f8b62bdef53d7e0bf102657c39ee0c30ead287efe25fae0351b71d5b1',
 'Tests/screenshot_baseline.py': '3f175e5ad1f9f2e5c79e4e3e09503f77801a37fb10ed328665d86452c4a6cc55',
 'Tests/settings_hierarchy_baseline.json': '701c83c22c813074ac47d65d7246f7e1c898b1648d09282c7c2c044cf5ce2c3f',
 'Tests/settings_hierarchy_baseline.py': '9708dfebfd134089adcae4999258edba3ef4b988e6e22249d267de471143e355',
 'Tests/settings_layout_baseline.json': 'aac85e23975eb527f466534d7f074ec64197dd2fcaff2cca214edbb49bf0b73a',
 'Tests/settings_layout_baseline.py': '11b07012b3f33066fe059f9ed7fa5f50a7aace690264d9ad75b1fbec69ae0858'}


def source_mutants(text, edits):
    mutants = [('unrelated', text + '\n// unrelated drift\n'),
               ('crlf', text.replace('\n', '\r\n')),
               ('mixed-crlf', text.replace('\n', '\r\n', 1)),
               ('byte', ('X' if text[0] != 'X' else 'Y') + text[1:]),
               ('truncated', text[:-1])]
    for i, edit in enumerate(edits):
        mutants.extend([(f'missing-{i}', text.replace(edit['after'], '', 1)),
                        (f'duplicate-{i}', text + edit['after']),
                        (f'indented-{i}', text.replace(edit['after'], ' ' + edit['after'], 1))])
    if len(edits) > 1:
        mutants.append(('hunk-order', text.replace(edits[0]['after'], '__MUTE_SWAP__', 1)
                        .replace(edits[-1]['after'], edits[0]['after'], 1)
                        .replace('__MUTE_SWAP__', edits[-1]['after'], 1)))
    else:
        lines = text.splitlines(keepends=True)
        lines[0], lines[1] = lines[1], lines[0]
        mutants.append(('line-order', ''.join(lines)))
    return mutants


def manifest_mutants(fixture):
    mutants = []
    for key in fixture:
        item = copy.deepcopy(fixture); del item[key]
        mutants.append(('missing-' + key, item))
    item = copy.deepcopy(fixture); item['unexpected'] = True
    mutants.append(('extra-top', item))
    item = copy.deepcopy(fixture); item['baseline'] = '0' * 40
    mutants.append(('baseline', item))
    for key in ('frozen', 'hunks', 'candidate_added_sha256'):
        for operation in ('missing', 'extra', 'type'):
            item = copy.deepcopy(fixture)
            if operation == 'missing': del item[key][next(iter(item[key]))]
            elif operation == 'extra': item[key]['Unexpected.swift'] = 'not authorized'
            else: item[key] = []
            mutants.append((key + '-' + operation, item))
    for path in fixture['hunks']:
        for value in ([], {}, None):
            item = copy.deepcopy(fixture); item['hunks'][path] = value
            mutants.append(('hunks-' + path, item))
        for key, values in {'count': [True, False, 0, 2, '1', 1.0, None],
                            'before': [None, [], 1, '', 'no newline'],
                            'after': [None, [], 1, '', 'no newline']}.items():
            for value in values:
                item = copy.deepcopy(fixture); item['hunks'][path][0][key] = value
                mutants.append((path + '-' + key, item))
        for operation in ('extra-key', 'missing-key', 'identity'):
            item = copy.deepcopy(fixture); edit = item['hunks'][path][0]
            if operation == 'extra-key': edit['extra'] = True
            elif operation == 'missing-key': del edit['count']
            else: edit['before'] = edit['after']
            mutants.append((path + '-' + operation, item))
    item = copy.deepcopy(fixture); item['frozen']['Makefile'] = '0' * 64
    mutants.append(('frozen-digest', item))
    item = copy.deepcopy(fixture); item['candidate_added_sha256'][ADDED] = '0' * 64
    mutants.append(('added-digest', item))
    return mutants


class SystemMuteBaselineContracts(unittest.TestCase):
    def helper(self):
        self.assertIsNotNone(importlib.util.find_spec('system_mute_baseline'), 'Missing exact system-mute inverse')
        return importlib.import_module('system_mute_baseline')

    def test_all_27_inherited_inputs_and_added_provider(self):
        h = self.helper()
        self.assertEqual(h.FIXTURE['baseline'], BASELINE)
        self.assertEqual(len(h.FIXTURE['frozen']), 27)
        self.assertEqual(len(h.FIXTURE['hunks']), 7)
        self.assertEqual(sum(map(len, h.FIXTURE['hunks'].values())), 10)
        self.assertEqual(hashlib.sha256(json.dumps(h.FIXTURE['frozen'], sort_keys=True).encode()).hexdigest(), MAP_SHA)
        for path, frozen in h.FIXTURE['frozen'].items():
            with self.subTest(path=path):
                self.assertEqual(h.digest(h.accepted_source(path)), frozen)
        self.assertNotIn(ADDED, h.FIXTURE['frozen'])
        self.assertEqual(h.FIXTURE['candidate_added_sha256'], {ADDED: ADDED_SHA})
        raw = (ROOT / ADDED).read_bytes().decode('utf-8')
        self.assertEqual(h.invert_system_mute(ADDED, raw), raw)

    def test_every_source_mutation_rejected_without_history(self):
        h = self.helper()
        with mock.patch('subprocess.run', side_effect=AssertionError('history unavailable')), \
             mock.patch('subprocess.check_output', side_effect=AssertionError('history unavailable')):
            for path in h.FROZEN_PATHS | h.ADDED_PATHS:
                text = (ROOT / path).read_bytes().decode('utf-8')
                for kind, mutant in source_mutants(text, h.FIXTURE['hunks'].get(path, [])):
                    self.assertNotEqual(mutant, text)
                    with self.subTest(path=path, mutation=kind), self.assertRaises(AssertionError):
                        h.invert_system_mute(path, mutant)

    def test_manifest_schema_and_types_fail_closed(self):
        h = self.helper()
        for kind, fixture in manifest_mutants(h.FIXTURE):
            with self.subTest(mutation=kind), mock.patch.object(h, 'FIXTURE', fixture):
                with self.assertRaises(AssertionError): h.accepted_source('Shared/Preferences.swift')

    def test_complete_line_unique_order_and_forward_replay(self):
        h = self.helper()
        for path, edits in h.FIXTURE['hunks'].items():
            current = (ROOT / path).read_bytes().decode('utf-8')
            restored = h.invert_system_mute(path, current)
            for side, text in (('after', current), ('before', restored)):
                end = -1
                for edit in edits:
                    starts = h._line_starts(text, edit[side])
                    self.assertEqual(len(starts), 1)
                    self.assertGreaterEqual(starts[0], end)
                    end = starts[0] + len(edit[side].splitlines(keepends=True))
            for edit in reversed(edits): restored = restored.replace(edit['before'], edit['after'], 1)
            self.assertEqual(restored, current)

    def test_old_helpers_fixtures_and_oracle_are_byte_frozen(self):
        for path, expected in HISTORICAL_INPUT_SHA256.items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected)

    def test_candidate_only_empty_path_historical_suite(self):
        import os
        import shutil
        import subprocess
        import sys
        import tempfile
        modules = ('test_system_mute_baseline', 'test_flashlight_baseline',
                   'test_settings_layout_baseline', 'test_app_switcher',
                   'test_control_center', 'test_notification_center', 'test_open_app',
                   'test_screenshot', 'test_settings_construction', 'test_settings_hierarchy',
                   'test_source', 'test_reference_settings', 'test_media_tracks',
                   'test_media_play_pause', 'test_flashlight', 'test_flashlight_ci')
        with tempfile.TemporaryDirectory(prefix='system-mute-candidate-only-') as directory:
            candidate = Path(directory) / 'candidate'
            shutil.copytree(ROOT, candidate, ignore=shutil.ignore_patterns('.git', '__pycache__', '.theos', '.build'))
            self.assertFalse((candidate / '.git').exists())
            # This focused set covers every historical byte/source consumer.
            # Shell-command expansion/completion protocol probes are exercised
            # by full discovery, not by this history-independent source suite.
            shell_protocols = (
                'test_each_native_uikit_feature_flag_expands_as_one_scalar_bash_argument',
                'test_real_native_parent_completion_command_rejects_zero_exit_child_without_report',
                'test_current_and_both_legacy_ui_compiles_always_receive_a_nonempty_scalar_feature_flag',
                'test_workflow_rejects_false_green_settings_child_with_no_completed_reports',
                'test_candidate_only_empty_path_historical_suite',
            )
            code = ("import unittest; modules=" + repr(modules) + "; "
                    "suite=unittest.TestSuite(); "
                    "[suite.addTests(unittest.defaultTestLoader.loadTestsFromName(m)) for m in modules]; "
                    "deflat=lambda s: [t for x in s for t in (deflat(x) if isinstance(x,unittest.TestSuite) else [x])]; "
                    "excluded=" + repr(shell_protocols) + "; "
                    "tests=[t for t in deflat(suite) if t.id().rsplit('.',1)[-1] not in excluded]; "
                    "assert len(tests) == 151; "
                    "result=unittest.TextTestRunner(verbosity=1).run(unittest.TestSuite(tests)); "
                    "assert result.wasSuccessful() and not result.skipped")
            result = subprocess.run([str(Path(sys.executable).resolve()), '-B', '-c', code],
                                    cwd=candidate / 'Tests',
                                    env={**os.environ, 'PATH': '', 'PYTHONPATH': str(candidate / 'Tests'),
                                         'PYTHONDONTWRITEBYTECODE': '1'},
                                    text=True, capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('skipped', result.stderr.lower())

    def test_unknown_paths_identity(self):
        h = self.helper(); text = 'unrelated\r\n'
        for path in ('Unexpected.swift', '../Shared/Preferences.swift', '/Shared/Preferences.swift', 'Shared/Preferences.swift.bak'):
            self.assertIs(h.invert_system_mute(path, text), text)

    def test_old_helpers_remain_strict_and_composition_is_explicit(self):
        import flashlight_baseline as old
        import settings_layout_baseline as layout
        from media_tracks_baseline import invert_media_tracks
        from media_play_pause_baseline import invert_media_play_pause
        h = self.helper(); path = 'Preferences/SettingsController.swift'
        with self.assertRaises(AssertionError): old.accepted_source(path)
        with self.assertRaises(AssertionError): layout.accepted_source(path, flashlight=True, media_tracks=True, media_play_pause=True)
        for path in h.FROZEN_PATHS:
            text = old.invert_flashlight(path, h.accepted_source(path))
            self.assertEqual(h.accepted_flashlight_source(path), text)
            tracks = invert_media_tracks(path, text)
            self.assertEqual(h.accepted_media_tracks_source(path), tracks)
            expected = layout.invert_settings_layout(path, invert_media_play_pause(path, tracks))
            self.assertEqual(h.accepted_layout_source(path, flashlight=True, media_tracks=True, media_play_pause=True), expected)

    def test_raw_byte_reader_and_missing_input(self):
        h = self.helper(); path = 'Shared/Preferences.swift'
        with mock.patch.object(h, 'ROOT') as root:
            file = root.__truediv__.return_value; file.is_file.return_value = True
            file.read_bytes.return_value = (ROOT / path).read_bytes()
            self.assertEqual(h.digest(h.accepted_source(path)), h.FIXTURE['frozen'][path])
            file.read_bytes.assert_called_once_with(); file.read_text.assert_not_called()
            file.read_bytes.return_value = file.read_bytes.return_value.replace(b'\n', b'\r\n')
            with self.assertRaises(AssertionError): h.accepted_source(path)
            file.is_file.return_value = False
            with self.assertRaisesRegex(AssertionError, 'Missing implementation'): h.accepted_source(path)


if __name__ == '__main__':
    unittest.main()
