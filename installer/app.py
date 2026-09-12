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

from core import DEFAULT_MANIFEST, Engine, Failure, display_name_value, https_url, save_json


PORT_PROFILES = (
    {
        'id': 'guacamoleb-crdroid-16',
        'label': 'OnePlus 7 / crDroid Android 16',
        'devices': ('OnePlus7', 'guacamoleb'),
        'properties': {
            'ro.build.version.sdk': '36',
            'ro.crdroid.version': '16.0',
            'ro.boot.project_codename': 'guacamoleb',
            'ro.board.platform': 'msmnile',
        },
        'kernel_prefix': '4.14.',
        'source_url': 'https://github.com/crdroidandroid/android_kernel_oneplus_sm8150.git',
        'source_ref': '16.0',
        'target': 'Image.gz-dtb',
    },
)


def clean_answer(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        text = text[1:-1].strip()
    return text


def choice(text, values):
    text = clean_answer(text).lower().lstrip(':').strip()
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
        self.verbose = os.environ.get('DETERMINATION_VERBOSE') == '1'
        self.current_phase = ''
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
            self.current_phase = event['phase']
            print(f'  {self.current_phase}...', flush=True)
            return
        if 'download' in event:
            received = event['received']
            total = event['total']
            print(f'\r  {event["download"]}: {received * 100 // total:3d}%', end='', flush=True)
            if received == total:
                print('', flush=True)
        if 'log' in event:
            text = event['log']
            if text == self.current_phase:
                return
            if not self.verbose:
                if text.startswith(('Using verified cache:', 'Verified recovery backup:',
                                    'Built installable port:', 'Extracted host magiskboot:')):
                    print(f'  {text}', flush=True)
                return
            if text.startswith('$ '):
                print(f'\n{self.palette.faint(text)}', flush=True)
            elif text and not text.startswith('=='):
                print(f'  {text}', flush=True)

    def banner(self):
        print()
        print(self.palette.title('  AURORA'))
        print(self.palette.accent('  Android convergence installer'))
        print(self.palette.faint('  A linear interview for building, installing, and recovering the phone.'))
        if not self.verbose:
            print(self.palette.faint('  Set DETERMINATION_VERBOSE=1 for full commands and probe output.'))
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
        aliases = {'y': 'yes', 'n': 'no', '1': 'yes', '2': 'no'}
        def valid(text):
            text = clean_answer(text).lower()
            return choice(aliases.get(text, text), ('yes', 'no'))
        value = self.ask(label + ' (yes/no)', 'yes' if default else 'no', valid)
        return value == 'yes'

    def one_of(self, label, values, default, descriptions=None):
        descriptions = descriptions or {}
        print(f'\n  {label}:', flush=True)
        for number, value in enumerate(values, 1):
            detail = descriptions.get(value)
            suffix = f' — {detail}' if detail else ''
            marker = ' (recommended)' if value == default else ''
            print(f'    {number}. {value}{marker}{suffix}', flush=True)

        def valid(text):
            text = clean_answer(text).lower().lstrip(':').strip()
            if text.isdigit() and 1 <= int(text) <= len(values):
                return values[int(text) - 1]
            return choice(text, values)

        default_number = values.index(default) + 1
        return self.ask(f'Choose 1-{len(values)} or type a name', default_number, valid)

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

    def local_manifest(self):
        candidates = [
            self.repo / 'dist/online-release/determination-update.json',
            self.engine.workspace / 'determination-update.json',
        ]
        candidates.extend(sorted(
            self.engine.workspace.glob('ports/*/bundle-*/determination-update.json'),
            key=lambda path: path.stat().st_mtime if path.exists() else 0,
            reverse=True,
        ))
        return next((str(path.resolve()) for path in candidates if path.is_file()), None)

    def port_profile(self):
        devices = {value.lower() for value in self.device.get('devices', ())}
        properties = self.device.get('properties', {})
        matches = []
        for profile in PORT_PROFILES:
            if not devices.intersection(value.lower() for value in profile['devices']):
                continue
            if any(properties.get(key) != value for key, value in profile['properties'].items()):
                continue
            if not self.device.get('kernel', '').startswith(profile['kernel_prefix']):
                continue
            matches.append(profile)
        if len(matches) > 1:
            raise Failure('More than one kernel source profile matches this phone.')
        return matches[0] if matches else None

    @staticmethod
    def valid_kernel_source(path):
        path = Path(path).expanduser()
        return (path / 'Makefile').is_file() and (path / 'scripts/kconfig/merge_config.sh').is_file()

    def kernel_source_matches(self, path, profile):
        if not self.valid_kernel_source(path):
            return False
        try:
            remote, _ = self.engine.run(['git', '-C', path, 'remote', 'get-url', 'origin'])
            branch, _ = self.engine.run(['git', '-C', path, 'branch', '--show-current'])
        except Failure:
            return False
        normalize = lambda value: value.strip().removesuffix('/').removesuffix('.git')
        return normalize(remote) == normalize(profile['source_url']) and branch.strip() == profile['source_ref']

    def automatic_kernel_source(self, profile):
        override = os.environ.get('DETERMINATION_KERNEL_SOURCE')
        if override:
            if override.startswith('https://'):
                return https_url(override)
            if not self.valid_kernel_source(override):
                raise Failure('DETERMINATION_KERNEL_SOURCE is not a usable kernel source tree.')
            return str(Path(override).expanduser().resolve())
        candidates = (
            self.repo / 'kernel/src',
            self.engine.workspace / 'sources' / profile['id'],
            self.engine.workspace / 'sources' / self.device['device'],
        )
        for path in candidates:
            if self.kernel_source_matches(path, profile):
                return str(path.resolve())
        return profile['source_url']

    def automatic_distro(self, manifest, preferred=None):
        preferred = os.environ.get('DETERMINATION_DISTRO') or preferred or self.settings.get('distro') or 'debian'
        if preferred not in ('debian', 'arch', 'alpine'):
            raise Failure('DETERMINATION_DISTRO must be debian, arch, or alpine.')
        available = []
        if manifest and not manifest.startswith('https://'):
            data = self.engine.load_manifest(manifest)
            for item in data['artifacts']:
                if item['type'] != 'rootfs':
                    continue
                if item.get('devices') and not set(item['devices']) & set(self.device['devices']):
                    continue
                if item.get('abis') and not set(item['abis']) & set(self.device['abis']):
                    continue
                available.append(item['distro'])
        available = list(dict.fromkeys(available))
        selected = preferred if not available or preferred in available else ('debian' if 'debian' in available else available[0])
        reason = 'only compatible desktop in the bundle' if len(available) == 1 else 'saved/default desktop choice'
        print(f'  Linux desktop: {selected} ({reason})', flush=True)
        return selected

    def manifest(self, default=None, purpose='Install bundle'):
        def valid(text):
            text = clean_answer(text)
            if text.startswith(('https:', 'http:')):
                return https_url(text)
            path = Path(text).expanduser()
            if path.is_dir():
                path = path / 'determination-update.json'
            if not text or not path.is_file():
                raise Failure(
                    'That bundle was not found. Enter its determination-update.json file, '
                    'the folder containing that file, or an HTTPS URL.'
                )
            return str(path.resolve())

        suggested = default or self.settings.get('manifest') or DEFAULT_MANIFEST or self.local_manifest()
        print(f'\n  {purpose}:', flush=True)
        print('    This is the determination-update.json file that lists every install file', flush=True)
        print('    and its checksum. You may paste the JSON file, its folder, or an HTTPS URL.', flush=True)
        if not suggested:
            print(self.palette.faint(
                '    No bundle was found automatically. Build or download a complete bundle first.'
            ), flush=True)
        if suggested:
            selected = valid(suggested)
            print(f'    Detected automatically: {selected}', flush=True)
            return selected
        return self.ask('Bundle file or URL', None, valid)

    def kernel_source(self):
        def valid(text):
            text = clean_answer(text)
            if text.startswith(('https:', 'http:')):
                return https_url(text)
            path = Path(text).expanduser()
            if not path.is_dir():
                raise Failure('Enter an existing kernel source folder or an HTTPS Git repository URL.')
            return str(path.resolve())

        saved = self.settings.get('kernel_source')
        if saved and not (saved.startswith('https://') or Path(saved).expanduser().is_dir()):
            saved = None
        print('\n  Android needs the kernel source matching the ROM currently on this phone.', flush=True)
        print('    Local example: /home/you/src/android_kernel_oneplus_sm8150', flush=True)
        print('    Git example:   https://github.com/vendor/android_kernel_oneplus_sm8150', flush=True)
        return self.ask('Kernel source folder or HTTPS Git URL', saved, valid)

    def remember(self, **values):
        self.settings.update(values)
        save_json(self.settings_path, self.settings)

    def host_tools(self):
        if not shutil.which(self.engine.adb):
            local_adb = Path.home() / 'platform-tools/adb'
            self.engine.adb = str(local_adb) if local_adb.is_file() else self.path('ADB executable', must_exist=True)
        if not shutil.which(self.engine.magiskboot):
            local_magiskboot = self.repo / 'toolchain/usr/bin/magiskboot'
            if local_magiskboot.is_file() and os.access(local_magiskboot, os.X_OK):
                self.engine.magiskboot = str(local_magiskboot)
            else:
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
        if len(authorized) == 1:
            serial = authorized[0]
            print(f'  Selected automatically: {serial}', flush=True)
        else:
            serial = self.ask('ADB serial', None, lambda text: choice(text, authorized))
        self.engine.serial = serial
        return serial

    def inspect(self):
        self.serial()
        self.device = self.engine.inspect(self.engine.serial)
        properties = self.device['properties']
        print(f'\n  {self.palette.good("Device accepted")}: {self.device["model"]} ({self.device["device"]})', flush=True)
        rom = properties.get('ro.crdroid.build.version')
        release = properties.get('ro.build.version.release')
        sdk = properties.get('ro.build.version.sdk')
        os_name = f'crDroid {rom} / ' if rom else ''
        print(f'  OS:      {os_name}Android {release} (SDK {sdk})', flush=True)
        print(f'  Build:   {self.device["fingerprint"]}', flush=True)
        print(f'  Kernel:  {self.device["kernel"]}', flush=True)
        print(f'  Slot:    {self.device["slot"] or "single"}', flush=True)
        print(f'  Battery: {self.device["battery"]}%', flush=True)
        missing = ', '.join(self.device['missing']) or 'none'
        if missing == 'none':
            print('  Kernel readiness: this kernel already has every required option.', flush=True)
        else:
            print(f'  Kernel readiness: the new build must enable {missing}', flush=True)

    def common(self):
        if self.device is None:
            self.inspect()

    def install(self, manifest_default=None, distro_default=None):
        self.common()
        manifest = self.manifest(manifest_default)
        distro = self.automatic_distro(manifest, distro_default)
        display_name = self.ask(
            'Your name in Linux',
            self.settings.get('display_name', 'Aurora User'),
            display_name_value,
        )
        hostname = self.ask('Guest hostname', self.settings.get('hostname', 'aurora'), hostname_value)
        self.remember(manifest=manifest, distro=distro, display_name=display_name, hostname=hostname)
        experimental = True
        prepare_only = self.yes_no('Prepare and verify only; do not install or flash', False)
        if not prepare_only:
            if not self.yes_no('Continue with installation', False):
                print('  Installation cancelled.', flush=True)
                return
        plan = self.engine.install(
            self.device,
            manifest,
            distro,
            hostname,
            experimental,
            prepare_only,
            display_name=display_name,
        )
        print(f'\n{self.palette.good("Complete")}: {plan["status"]}', flush=True)
        if plan.get('backup'):
            print(f'  Boot backup: {plan["backup"]}', flush=True)
        if not prepare_only and self.yes_no('Reboot the phone now', False):
            self.engine.run(self.engine.adb_args('reboot'))

    def port(self):
        self.common()
        profile = self.port_profile()
        if not self.device.get('config'):
            known_config = self.repo / 'artifacts/kernel-config-full.txt' if profile else None
            if known_config and known_config.is_file():
                self.device['config'] = known_config.read_text()
                print(f'  Kernel configuration: detected {known_config}', flush=True)
            else:
                print('  Android could not expose its running kernel settings.', flush=True)
                config = self.path('Matching running kernel configuration', must_exist=True)
                self.device['config'] = Path(config).read_text()
        if profile:
            print(f'\n  Port profile: {profile["label"]} (exact device, SDK, ROM, and kernel match)', flush=True)
            source = self.automatic_kernel_source(profile)
            ref = os.environ.get('DETERMINATION_KERNEL_REF', profile['source_ref'])
            target = os.environ.get('DETERMINATION_KERNEL_TARGET', profile['target'])
            print(f'  Kernel source: {source}', flush=True)
            print(f'  Kernel branch: {ref}', flush=True)
            print(f'  Kernel target: {target}', flush=True)
        else:
            print('\n  No exact maintained port profile matched this phone; source details are required.', flush=True)
            source = self.kernel_source()
            ref = os.environ.get('DETERMINATION_KERNEL_REF', '')
            target = os.environ.get('DETERMINATION_KERNEL_TARGET', 'Image')
        if source.startswith('https://'):
            if not ref:
                print('  Use the branch or tag for the Android build shown above.', flush=True)
                ref = self.ask('Kernel branch or tag', self.settings.get('kernel_ref'))
            if not ref:
                raise Failure('Enter the matching kernel branch or tag.')
            self.remember(kernel_source=source, kernel_ref=ref)
            source = self.engine.fetch_source(source, ref, profile['id'] if profile else self.device['device'])
        else:
            self.remember(kernel_source=source)
        jobs = jobs_value(os.environ.get('DETERMINATION_BUILD_JOBS', str(min(os.cpu_count() or 2, 16))))
        overrides = compiler_value(os.environ.get('DETERMINATION_KERNEL_MAKE_ARGS', ''))
        print(f'  Build settings: {jobs} jobs; ROM toolchain defaults', flush=True)
        manifest = self.manifest(purpose='Base bundle for the Linux desktop and companion app')
        distro = self.automatic_distro(manifest, 'debian')
        result = self.engine.port(self.device, source, target, jobs, manifest, distro, overrides)
        print(f'\n{self.palette.good("Port built")}: {result}', flush=True)
        self.remember(manifest=result, distro=distro)
        if self.yes_no('Continue with this bundle in the installation interview', True):
            self.install(result, distro)

    def recovery(self):
        self.common()
        action = self.one_of(
            'Repair or recovery task',
            ('backup', 'restore', 'verify', 'reboot'),
            'backup',
            {
                'backup': 'save and verify the current boot image on this PC',
                'restore': 'write a previously saved boot image back to this phone',
                'verify': 'check an installed Aurora system',
                'reboot': 'restart the selected phone',
            },
        )
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
            action = self.one_of(
                'What do you want to do',
                ('install', 'port', 'recovery'),
                'install',
                {
                    'install': 'install a ready-made bundle on this phone',
                    'port': 'build a matching kernel and bundle for this phone',
                    'recovery': 'back up, restore, verify, or reboot',
                },
            )
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
    parser = argparse.ArgumentParser(prog='aurora-installer', description='Aurora PC porting and installation interview')
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
