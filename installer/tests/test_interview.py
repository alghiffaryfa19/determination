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
from test_core import device


class InterviewTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.engine = Engine(self.directory.name)
        self.interview = Interview(self.engine)

    def test_manifest_requires_explicit_source_without_distributor_default(self):
        with patch('builtins.input', return_value='https://example.org/determination-update.json'):
            self.assertEqual(self.interview.manifest(), 'https://example.org/determination-update.json')

    def test_invalid_answer_repeats_same_question(self):
        with patch('builtins.input', side_effect=['maybe', 'yes']) as read, contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(self.interview.yes_no('Continue'))
        self.assertEqual(read.call_count, 2)

    def test_local_manifest_with_spaces(self):
        path = Path(self.directory.name) / 'local manifest.json'
        path.write_text('{}')
        with patch('builtins.input', return_value=str(path)):
            self.assertEqual(self.interview.manifest(), str(path))

    def test_complete_install_interview_passes_validated_values(self):
        self.interview.device = device()
        manifest = DEFAULT_MANIFEST or 'https://example.org/determination-update.json'
        answers = [manifest, 'debian', 'Determination User', 'workstation', 'yes']
        with patch('builtins.input', side_effect=answers), contextlib.redirect_stdout(io.StringIO()), \
             patch.object(self.engine, 'install', return_value={'status': 'prepared'}) as install:
            self.interview.install()
        install.assert_called_once_with(
            device(), manifest, 'debian', 'workstation', True, True,
            display_name='Determination User',
        )
        saved = json.loads(self.interview.settings_path.read_text())
        self.assertEqual(saved['hostname'], 'workstation')
        self.assertEqual(saved['display_name'], 'Determination User')
        self.assertNotIn('experimental', saved)

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
