import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import Engine, Failure
from pipeline import Pipeline, Stage


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.engine = Engine(self.root)
        self.source = self.root / 'source'
        self.source.write_text('first')

    def stages(self):
        first = self.root / 'first'
        second = self.root / 'second'
        command = (sys.executable, '-c',
                   'import pathlib,sys; pathlib.Path(sys.argv[2]).write_bytes(pathlib.Path(sys.argv[1]).read_bytes())')
        return [Stage('first', 'First', (self.source,), (first,), (*command, str(self.source), str(first))),
                Stage('second', 'Second', (), (second,), (*command, str(first), str(second)), ('first',))]

    def test_resume_rechecks_content_and_propagates_input_changes(self):
        recipe = Pipeline(self.engine, 'test', self.stages())
        recipe.run()
        self.assertTrue(all(s['status'] == 'cached' for s in recipe.plan()['stages']))
        self.source.write_text('second')
        recipe = Pipeline(self.engine, 'test', self.stages())
        self.assertTrue(all(s['status'] == 'pending' for s in recipe.plan()['stages']))
        recipe.run()
        self.assertEqual((self.root / 'second').read_text(), 'second')
        (self.root / 'first').write_text('corrupt')
        self.assertEqual(recipe.plan()['stages'][0]['status'], 'pending')
        recipe.run()
        self.assertEqual((self.root / 'first').read_text(), 'second')

    def test_missing_output_is_a_failure_and_can_resume(self):
        stage = Stage('bad', 'Bad', (), (self.root / 'missing',), (sys.executable, '-c', 'pass'))
        recipe = Pipeline(self.engine, 'test', [stage])
        with self.assertRaises(Failure):
            recipe.run()
        saved = json.loads(recipe.path.read_text())
        self.assertEqual(saved['stages']['bad']['status'], 'failed')
        self.assertEqual(Pipeline(self.engine, 'test', [stage]).plan()['stages'][0]['status'], 'pending')

    def test_failed_dependencies_stop_dependents(self):
        stages = self.stages()
        stages[0] = Stage('first', 'First', (), (), (sys.executable, '-c', 'raise SystemExit(7)'))
        recipe = Pipeline(self.engine, 'test', stages)
        with self.assertRaises(Failure):
            recipe.run()
        self.assertNotIn('second', recipe.state['stages'])

    def test_cycles_and_unknown_dependencies_rejected(self):
        for dependency in ('a', 'missing'):
            with self.assertRaises(Failure):
                Pipeline(self.engine, 'test', [Stage('a', 'A', (), (), (), (dependency,))])

    def test_workspace_lock_releases_after_process_death(self):
        child = subprocess.Popen([sys.executable, '-u', '-c',
            'from core import Engine; import sys,time; '
            'e=Engine(sys.argv[1]); '
            'lock=e.transaction(); lock.__enter__(); print("locked"); time.sleep(30)', str(self.root)],
            cwd=Path(__file__).resolve().parents[1], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'locked')
            with self.assertRaises(Failure), self.engine.transaction():
                pass
            child.kill()
            child.wait(timeout=5)
            with self.engine.transaction():
                pass
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            child.stdout.close()

    def test_machine_plan_needs_no_device_or_existing_build(self):
        result = subprocess.run([sys.executable, 'app.py', 'build-plan', '--json',
                                 '--workspace', str(self.root)],
                                cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(plan['schema'], 1)
        self.assertTrue(all(s['status'] == 'pending' for s in plan['stages']))
        self.assertFalse((self.root / 'builds/arch/work').exists())
