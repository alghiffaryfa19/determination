from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import time

from core import Failure, digest, save_json


@dataclass(frozen=True)
class Stage:
    id: str
    label: str
    inputs: tuple[Path, ...]
    outputs: tuple[Path, ...]
    command: tuple[str, ...]
    dependencies: tuple[str, ...] = ()
    timeout: int = 14400


class Pipeline:
    """A journalled DAG shared by interactive and non-interactive frontends."""

    def __init__(self, engine, name, stages, options=None):
        self.engine = engine
        self.stages = {stage.id: stage for stage in stages}
        if len(self.stages) != len(stages):
            raise Failure('Duplicate build stage ID.')
        self.options = options or {}
        self.path = engine.workspace / 'builds' / name / 'state.json'
        self.state = {'schema': 1, 'stages': {}}
        if self.path.exists():
            try:
                self.state = json.loads(self.path.read_text())
                if self.state.get('schema') != 1 or not isinstance(self.state.get('stages'), dict):
                    raise ValueError('unsupported state schema')
            except (ValueError, AttributeError) as exc:
                raise Failure(f'Cannot read build journal {self.path}: {exc}') from exc
        self.order = []
        active = set()

        def visit(name):
            if name in active:
                raise Failure(f'Build dependency cycle at {name}.')
            if name in self.order:
                return
            if name not in self.stages:
                raise Failure(f'Unknown build dependency: {name}')
            active.add(name)
            for dependency in self.stages[name].dependencies:
                visit(dependency)
            active.remove(name)
            self.order.append(name)

        for name in self.stages:
            visit(name)

    @staticmethod
    def hashes(paths):
        result = {}
        for path in paths:
            if not path.is_file():
                raise Failure(f'Required build file is missing: {path}')
            result[str(path)] = digest(path)
        return result

    def key(self, stage):
        data = {
            'command': stage.command, 'options': self.options,
            'inputs': self.hashes(stage.inputs),
            'dependencies': {name: self.state['stages'].get(name, {}).get('outputs')
                             for name in stage.dependencies},
        }
        return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()

    def cached(self, stage, key):
        previous = self.state['stages'].get(stage.id, {})
        if previous.get('status') != 'complete' or previous.get('key') != key:
            return False
        try:
            return bool(stage.outputs) and previous.get('outputs') == self.hashes(stage.outputs)
        except Failure:
            return False

    def plan(self):
        result = []
        pending = set()
        for name in self.order:
            stage = self.stages[name]
            try:
                cached = not pending.intersection(stage.dependencies) and self.cached(stage, self.key(stage))
            except Failure:
                cached = False
            if not cached:
                pending.add(name)
            result.append({'id': name, 'label': stage.label,
                           'status': 'cached' if cached else 'pending',
                           'dependencies': list(stage.dependencies),
                           'command': list(stage.command),
                           'outputs': [str(p) for p in stage.outputs]})
        return {'schema': 1, 'stages': result, 'journal': str(self.path)}

    def run(self, cwd=None, env=None):
        # The caller holds Engine.transaction across the entire operation.
        for name in self.order:
            stage = self.stages[name]
            key = self.key(stage)
            if self.cached(stage, key):
                self.engine.emit({'stage': name, 'status': 'cached'})
                continue
            record = {'status': 'running', 'key': key, 'started': time.time()}
            self.state['stages'][name] = record
            save_json(self.path, self.state)
            self.engine.emit({'stage': name, 'status': 'running'})
            self.engine.phase(stage.label)
            try:
                self.engine.run(stage.command, cwd=cwd, env=env, timeout=stage.timeout)
                record['outputs'] = self.hashes(stage.outputs)
                record['status'] = 'complete'
            except BaseException as exc:
                record.update(status='failed', error=str(exc) or type(exc).__name__)
                raise
            finally:
                record['finished'] = time.time()
                save_json(self.path, self.state)
                self.engine.emit({'stage': name, 'status': record['status']})
        return self.plan()
