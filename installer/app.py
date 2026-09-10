#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sys
import time

from core import DEFAULT_MANIFEST, Engine, Failure, https_url, save_json


def choice(text, values):
    if text not in values:
        raise Failure('Use one of: ' + ', '.join(values) + '.')
    return text


def hostname_value(text):
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', text):
        raise Failure('Use lowercase letters, digits, and internal hyphens.')
    return text


def jobs_value(text):
    if not text.isdigit() or not 1 <= int(text) <= 256:
        raise Failure('Use an integer from 1 to 256.')
    return int(text)


def compiler_value(text):
    for value in shlex.split(text):
        if not re.fullmatch(r'(CC|LD|AR|NM|OBJCOPY|OBJDUMP|STRIP|CROSS_COMPILE|CROSS_COMPILE_ARM32|LLVM|LLVM_IAS)=[A-Za-z0-9_./+-]+', value):
            raise Failure('Overrides must be compiler or LLVM make assignments.')
    return text


class Palette:
    def __init__(self):
        self.enabled = sys.stdout.isatty() and os.environ.get('TERM') not in ('', 'dumb')

    def wrap(self, code, value):
        return f'\033[{code}m{value}\033[0m' if self.enabled else value

    def title(self, value):
        return self.wrap('1;38;5;117', value)

    def accent(self, value):
        return self.wrap('38;5;141', value)

    def faint(self, value):
        return self.wrap('2;37', value)

    def good(self, value):
        return self.wrap('38;5;114', value)

    def bad(self, value):
        return self.wrap('1;38;5;203', value)

    def prompt(self, value):
        return self.wrap('1;38;5;221', value)


class Interview:
    def __init__(self, engine):
        self.engine = engine
        self.palette = Palette()
        self.device = None
        self.repo = Path(__file__).resolve().parents[1]
        self.engine.emit = self.event
        self.settings_path = self.engine.workspace / 'settings.json'
        try:
            self.settings = json.loads(self.settings_path.read_text())
            if not isinstance(self.settings, dict):
                self.settings = {}
        except (OSError, ValueError):
            self.settings = {}

    def event(self, event):
        if 'phase' in event:
            return
        if 'download' in event:
            received = event['received']
            total = event['total']
            print(f'\r  {event["download"]}: {received * 100 // total:3d}%', end='', flush=True)
            if received == total:
                print('', flush=True)
        if 'log' in event:
            text = event['log']
            if text.startswith('$ '):
                print(f'\n{self.palette.faint(text)}', flush=True)
            elif text and not text.startswith('=='):
                print(f'  {text}', flush=True)

    def banner(self):
        print()
        print(self.palette.title('  DETERMINATION'))
        print(self.palette.accent('  PC porting and installation workbench'))
        print(self.palette.faint('  A linear interview for building, installing, and recovering the phone.'))
        print()

    def ask(self, label, default=None, validate=None):
        suffix = f' [{default}]' if default not in (None, '') else ''
        while True:
            try:
                stamp = time.strftime('%H:%M:%S')
                answer = input(self.palette.prompt(f'[{stamp}] {label}{suffix}: ')).strip()
            except EOFError:
                raise Failure('Input ended before the interview was complete.')
            if not answer and default is not None:
                answer = str(default)
            if validate is None:
                return answer
            try:
                value = validate(answer)
                if value is not None:
                    return value
            except (Failure, ValueError) as error:
                print(self.palette.bad(f'  {error}'), flush=True)

    def yes_no(self, label, default=False):
        value = self.ask(label + ' (yes/no)', 'yes' if default else 'no',
                         lambda text: choice(text.lower(), ('yes', 'no')))
        return value == 'yes'

    def one_of(self, label, values, default):
        allowed = ', '.join(values)
        return self.ask(f'{label} ({allowed})', default,
                        lambda text: choice(text, values))

    def path(self, label, default=None, directory=False, must_exist=False):
        def valid(text):
            if not text:
                raise Failure('Enter a path.')
            path = Path(text).expanduser()
            if must_exist and not path.exists():
                raise Failure(f'Path does not exist: {path}')
            if directory and must_exist and not path.is_dir():
                raise Failure(f'Not a directory: {path}')
            return str(path)
        return self.ask(label, default, valid)

    def manifest(self, default=None):
        def valid(text):
            if text.startswith(('https:', 'http:')):
                return https_url(text)
            path = Path(text).expanduser()
            if not text or not path.is_file():
                raise Failure('Enter an HTTPS manifest URL or an existing manifest file.')
            return str(path.resolve())
        return self.ask('Release manifest', default or self.settings.get('manifest', DEFAULT_MANIFEST), valid)

    def remember(self, **values):
        self.settings.update(values)
        save_json(self.settings_path, self.settings)

    def host_tools(self):
        if not shutil.which(self.engine.adb):
            self.engine.adb = self.path('ADB executable', must_exist=True)
        if not shutil.which(self.engine.magiskboot):
            print('  A host magiskboot executable is required to preserve your boot image.')
            if self.yes_no('Extract magiskboot from an official Magisk APK on this PC', True):
                apk = self.path('Magisk APK', must_exist=True)
                self.engine.magiskboot = self.engine.extract_magiskboot(apk)
            else:
                self.engine.magiskboot = self.path('Magiskboot executable', must_exist=True)
        self.engine.adb = shutil.which(self.engine.adb) or self.engine.adb
        self.engine.magiskboot = shutil.which(self.engine.magiskboot) or self.engine.magiskboot

    def serial(self):
        devices = self.engine.devices()
        if not devices:
            raise Failure('No ADB devices found. Connect one phone and enable USB debugging.')
        print('\n  Connected devices:', flush=True)
        for item in devices:
            state = self.palette.good(item['state']) if item['state'] == 'device' else self.palette.bad(item['state'])
            print(f'    {item["serial"]}  {state}  {item["details"]}', flush=True)
        authorized = [item['serial'] for item in devices if item['state'] == 'device']
        if not authorized:
            raise Failure('Authorize USB debugging on the phone, then run init again.')
        serial = self.ask('ADB serial', authorized[0] if len(authorized) == 1 else None,
                          lambda text: choice(text, authorized))
        self.engine.serial = serial
        return serial

    def inspect(self):
        self.serial()
        self.device = self.engine.inspect(self.engine.serial)
        print(f'\n  {self.palette.good("Device accepted")}: {self.device["model"]} ({self.device["device"]})', flush=True)
        print(f'  Android: {self.device["fingerprint"]}', flush=True)
        print(f'  Kernel:  {self.device["kernel"]}', flush=True)
        print(f'  Slot:    {self.device["slot"] or "single"}', flush=True)
        print(f'  Battery: {self.device["battery"]}%', flush=True)
        missing = ', '.join(self.device['missing']) or 'none'
        print(f'  Kernel options missing before port: {missing}', flush=True)

    def common(self):
        if self.device is None:
            self.inspect()

    def install(self, manifest_default=None, distro_default=None):
        self.common()
        manifest = self.manifest(manifest_default)
        distro = self.one_of('Linux distribution', ('debian', 'arch', 'alpine'), distro_default or self.settings.get('distro', 'debian'))
        hostname = self.ask('Guest hostname', self.settings.get('hostname', 'determination'), hostname_value)
        self.remember(manifest=manifest, distro=distro, hostname=hostname)
        experimental = self.yes_no('Allow experimental artifacts', False)
        prepare_only = self.yes_no('Prepare and verify only; do not install or flash', False)
        if not prepare_only:
            print(self.palette.bad('\n  Boot will be written only after the PC backup, repack, and readback checks pass.'), flush=True)
            if not self.yes_no('Continue with installation', False):
                print('  Installation cancelled.', flush=True)
                return
        plan = self.engine.install(self.device, manifest, distro, hostname, experimental, prepare_only)
        print(f'\n{self.palette.good("Complete")}: {plan["status"]}', flush=True)
        if plan.get('backup'):
            print(f'  Boot backup: {plan["backup"]}', flush=True)
        if not prepare_only and self.yes_no('Reboot the phone now', False):
            self.engine.run(self.engine.adb_args('reboot'))

    def port(self):
        self.common()
        reference = self.device['device'] in ('guacamoleb', 'OnePlus7')
        source_default = str(self.repo / 'kernel/src') if (self.repo / 'kernel/src/Makefile').is_file() else None
        if source_default is None and reference:
            source_default = 'https://github.com/crdroidandroid/android_kernel_oneplus_sm8150.git'
        source = self.ask('Matching ROM kernel source (local path or HTTPS repository)', source_default)
        if source.startswith('https://'):
            ref = self.ask('Kernel branch or tag', '16.0' if reference else 'main')
            source = self.engine.fetch_source(source, ref, self.device['device'])
        source = self.path('Kernel source directory', source, directory=True, must_exist=True)
        default_target = 'Image.gz-dtb' if self.device['device'] in ('guacamoleb', 'OnePlus7') else 'Image'
        target = self.one_of('Kernel image target', ('Image', 'Image.gz', 'Image.gz-dtb'), default_target)
        jobs = self.ask('Parallel build jobs', str(min(os.cpu_count() or 2, 16)), jobs_value)
        overrides = self.ask('Compiler make overrides', '', compiler_value)
        manifest = self.manifest()
        distro = self.one_of('Linux distribution for the generated bundle', ('debian', 'arch', 'alpine'), 'debian')
        result = self.engine.port(self.device, source, target, jobs, manifest, distro, overrides)
        print(f'\n{self.palette.good("Port built")}: {result}', flush=True)
        self.remember(manifest=result, distro=distro)
        if self.yes_no('Continue with this bundle in the installation interview', True):
            self.install(result, distro)

    def recovery(self):
        self.common()
        action = self.one_of('Recovery action', ('backup', 'restore', 'verify', 'reboot'), 'backup')
        if action == 'backup':
            path = self.engine.backup(self.device)
            print(f'\n{self.palette.good("Backup verified")}: {path}', flush=True)
        elif action == 'restore':
            backup = self.path('PC boot backup image', None, must_exist=True)
            if self.yes_no('Restore this boot image to the active slot', False):
                self.engine.restore(self.device, backup)
                print(f'\n{self.palette.good("Restore verified")}', flush=True)
        elif action == 'verify':
            self.engine.verify(self.device)
            print(f'\n{self.palette.good("Installation verified")}', flush=True)
        else:
            if self.yes_no('Reboot the selected phone', False):
                self.engine.run(self.engine.adb_args('reboot'))

    def run(self, command):
        self.banner()
        self.host_tools()
        if command == 'init':
            self.inspect()
            action = self.one_of('What should Determination do', ('install', 'port', 'recovery'), 'install')
        else:
            action = command
            self.inspect()
        if action == 'install':
            self.install()
        elif action == 'port':
            self.port()
        else:
            self.recovery()


def main():
    parser = argparse.ArgumentParser(prog='determination-installer', description='Determination linear PC porting and installation interview')
    parser.add_argument('command', nargs='?', choices=('init', 'install', 'port', 'recovery'), default='init')
    parser.add_argument('--workspace', default=str(Path.home() / '.local/share/determination'))
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--magiskboot', default='magiskboot')
    args = parser.parse_args()
    try:
        engine = Engine(args.workspace, adb=args.adb, magiskboot=args.magiskboot)
        with engine.transaction():
            Interview(engine).run(args.command)
    except (Failure, OSError, ValueError, KeyboardInterrupt) as error:
        print(f'\n{Palette().bad("Stopped: " + str(error))}', file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
