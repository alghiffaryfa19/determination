import contextlib
import io
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import Interview, compiler_value, jobs_value
from core import DEFAULT_MANIFEST, Engine, Failure, display_name_value
from test_core import bundle, device


class InterviewTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = Engine(self.directory.name)
        self.interview = Interview(self.engine)

    def test_manifest_requires_explicit_source_without_distributor_default(self):
        with patch('builtins.input', return_value='https://example.org/aurora-update.json'):
            self.assertEqual(self.interview.manifest(), 'https://example.org/aurora-update.json')

    def test_invalid_answer_repeats_same_question(self):
        with patch('builtins.input', side_effect=['maybe', 'yes']) as read, contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(self.interview.yes_no('Continue'))
        self.assertEqual(read.call_count, 2)

    def test_numbered_and_forgiving_choices(self):
        with patch('builtins.input', return_value='2'), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.one_of('Action', ('install', 'port', 'recovery'), 'install'), 'port')
        with patch('builtins.input', return_value=':PORT'), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.one_of('Action', ('install', 'port', 'recovery'), 'install'), 'port')

    def test_local_manifest_with_spaces(self):
        path = Path(self.directory.name) / 'local manifest.json'
        path.write_text('{}')
        with patch('builtins.input', return_value=str(path)):
            self.assertEqual(self.interview.manifest(), str(path))

    def test_manifest_accepts_the_bundle_directory(self):
        bundle = Path(self.directory.name) / 'friendly bundle'
        bundle.mkdir()
        manifest = bundle / 'aurora-update.json'
        manifest.write_text('{}')
        with patch('builtins.input', return_value=str(bundle)), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.manifest(), str(manifest.resolve()))

    def test_manifest_discovers_repo_bundle(self):
        repo = Path(self.directory.name) / 'repo'
        manifest = repo / 'dist/online-release/aurora-update.json'
        manifest.parent.mkdir(parents=True)
        manifest.write_text('{}')
        self.interview.repo = repo
        with patch('builtins.input', return_value=''), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.manifest(), str(manifest.resolve()))

    def test_kernel_source_accepts_folder_and_https_repo(self):
        source = Path(self.directory.name) / 'kernel source'
        source.mkdir()
        with patch('builtins.input', return_value=str(source)), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.kernel_source(), str(source.resolve()))
        with patch('builtins.input', return_value='https://example.org/kernel.git'), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.kernel_source(), 'https://example.org/kernel.git')

    def test_complete_install_interview_passes_validated_values(self):
        self.interview.device = device()
        manifest = DEFAULT_MANIFEST or 'https://example.org/aurora-update.json'
        answers = [manifest, 'Aurora User', 'workstation', 'yes']
        with patch('builtins.input', side_effect=answers), contextlib.redirect_stdout(io.StringIO()), \
             patch.object(self.engine, 'install', return_value={'status': 'prepared'}) as install:
            self.interview.install()
        install.assert_called_once_with(
            device(), manifest, 'arch', 'workstation', True, True,
            display_name='Aurora User',
        )
        saved = json.loads(self.interview.settings_path.read_text())
        self.assertEqual(saved['hostname'], 'workstation')
        self.assertEqual(saved['display_name'], 'Aurora User')
        self.assertNotIn('experimental', saved)

    def test_one_authorized_device_is_selected_without_a_prompt(self):
        rows = [{'serial': 'only-phone', 'state': 'device', 'details': 'model:test'}]
        with patch.object(self.engine, 'devices', return_value=rows), \
             patch('builtins.input') as read, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.serial(), 'only-phone')
        read.assert_not_called()

    def test_exact_rom_profile_autodetects_local_kernel_source(self):
        source = Path(self.directory.name) / 'repo/kernel/src'
        (source / 'scripts/kconfig').mkdir(parents=True)
        (source / 'Makefile').write_text('VERSION = 4\nPATCHLEVEL = 14\n')
        (source / 'scripts/kconfig/merge_config.sh').write_text('')
        self.interview.repo = Path(self.directory.name) / 'repo'
        self.interview.device = dict(
            device(), devices=['OnePlus7'], kernel='4.14.357-test',
            properties={'ro.build.version.sdk': '36', 'ro.crdroid.version': '16.0',
                        'ro.boot.project_codename': 'guacamoleb', 'ro.board.platform': 'msmnile'},
        )
        profile = self.interview.port_profile()
        self.assertEqual(profile['target'], 'Image.gz-dtb')
        with patch.object(self.engine, 'run', side_effect=[
            ('https://github.com/crdroidandroid/android_kernel_oneplus_sm8150.git', 0),
            ('16.0', 0),
        ]):
            self.assertEqual(self.interview.automatic_kernel_source(profile), str(source.resolve()))

    def test_spoofed_fingerprint_does_not_select_port_profile(self):
        self.interview.device = dict(
            device(), devices=['OnePlus7'], kernel='4.14.357-test',
            fingerprint='OnePlus/OnePlus7/OnePlus7:12/spoofed',
            properties={'ro.build.version.sdk': '35', 'ro.crdroid.version': '15.0',
                        'ro.boot.project_codename': 'guacamoleb', 'ro.board.platform': 'msmnile'},
        )
        self.assertIsNone(self.interview.port_profile())

    def test_single_manifest_distro_is_selected_without_a_prompt(self):
        bundle(self.directory.name)
        path = Path(self.directory.name) / 'manifest.json'
        self.interview.device = device()
        with patch('builtins.input') as read, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.automatic_distro(str(path)), 'debian')
        read.assert_not_called()

    def test_port_builds_its_base_bundle_without_a_manifest_prompt(self):
        source = Path(self.directory.name) / 'kernel'
        (source / 'scripts/kconfig').mkdir(parents=True)
        (source / 'Makefile').write_text('fixture')
        (source / 'scripts/kconfig/merge_config.sh').write_text('fixture')
        self.interview.device = dict(
            device(), devices=['OnePlus7'], kernel='4.14.357-test',
            properties={'ro.build.version.sdk': '36', 'ro.crdroid.version': '16.0',
                        'ro.boot.project_codename': 'guacamoleb', 'ro.board.platform': 'msmnile'},
        )
        generated = str(Path(self.directory.name) / 'generated/aurora-update.json')
        result = str(Path(self.directory.name) / 'port/aurora-update.json')
        with patch.object(self.interview, 'automatic_kernel_source', return_value=str(source)), \
             patch.object(self.interview, 'manifest') as manifest_prompt, \
             patch.object(self.interview, 'yes_no', return_value=False), \
             patch.object(self.engine, 'build_local_base_bundle', return_value=generated) as base, \
             patch.object(self.engine, 'port', return_value=result) as port, \
             contextlib.redirect_stdout(io.StringIO()):
            self.interview.port()
        manifest_prompt.assert_not_called()
        base.assert_called_once_with(self.interview.repo, self.interview.device, 'arch')
        port.assert_called_once_with(self.interview.device, str(source), 'Image.gz-dtb',
                                     unittest.mock.ANY, generated, 'arch', '')

    def test_multiple_devices_require_an_explicit_serial(self):
        rows = [{'serial': serial, 'state': 'device', 'details': ''} for serial in ('phone1', 'phone2')]
        with patch.object(self.engine, 'devices', return_value=rows), \
             patch('builtins.input', side_effect=['', 'phone2']), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.interview.serial(), 'phone2')

    def test_end_of_input_stops_without_installation(self):
        with patch('builtins.input', side_effect=EOFError), self.assertRaises(Failure):
            self.interview.ask('Device')

    def test_compiler_and_job_validation(self):
        for value in ('0', '257', 'x', '-1'):
            with self.assertRaises(Failure):
                jobs_value(value)
        with self.assertRaises(Failure):
            compiler_value('O=/tmp/wrong')
        self.assertEqual(compiler_value('LLVM=1 CC=clang'), 'LLVM=1 CC=clang')

    def test_display_name_validation(self):
        self.assertEqual(display_name_value('  Ada Lovelace  '), 'Ada Lovelace')
        for value in ('', 'name:admin', 'name,room', 'bad\nname', 'x' * 65):
            with self.subTest(value=value), self.assertRaises(Failure):
                display_name_value(value)

    @unittest.skipUnless(os.name == 'posix', 'POSIX signals required')
    def test_interrupt_is_deferred_during_mutation(self):
        old = signal.getsignal(signal.SIGINT)
        with self.engine.critical():
            signal.raise_signal(signal.SIGINT)
            self.engine.checkpoint()
            self.assertTrue(self.engine.protected)
        self.assertEqual(signal.getsignal(signal.SIGINT), old)
        self.assertFalse(self.engine.protected)
        with self.assertRaises(Failure):
            self.engine.checkpoint()


if __name__ == '__main__':
    unittest.main()
