from __future__ import annotations

import contextlib
import hashlib
import json
import os
import platform
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import signal
import subprocess
import tarfile
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from discovery import PARTITIONS, PROBES, partitions, profile_values

REPO = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = os.environ.get('DETERMINATION_UPDATE_MANIFEST_URL', '')
KINDS = ('module', 'runtime', 'rootfs', 'boot', 'companion')
LXC_TOOLS = {'lxc-start', 'lxc-stop', 'lxc-attach', 'lxc-info', 'lxc-ls', 'lxc-console', 'lxc-execute'}
REQUIRED = ('NAMESPACES', 'PID_NS', 'IPC_NS', 'USER_NS', 'NET_NS', 'CGROUPS', 'CGROUP_PIDS', 'VETH', 'OVERLAY_FS', 'ANDROID_BINDER_IPC', 'ANDROID_BINDERFS', 'SYNC_FILE', 'VT', 'POSIX_MQUEUE')


class Failure(RuntimeError):
    pass


class Cancelled(Failure):
    pass


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def save_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.new')
    with temporary.open('w') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def checked_word(value, label='value'):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,119}', value):
        raise Failure(f'Invalid {label}: {value!r}')
    return value


def https_url(value):
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise Failure('Downloads require an HTTPS URL without credentials.')
    return value


def display_name_value(value):
    if not isinstance(value, str):
        raise Failure('Enter a Linux display name.')
    value = value.strip()
    if not value:
        raise Failure('Enter a Linux display name.')
    if len(value) > 64 or any(not char.isprintable() or char in ':,' for char in value):
        raise Failure('Display name must be at most 64 printable characters without colon or comma.')
    return value


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        https_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def open_https(url):
    return urllib.request.build_opener(HTTPSRedirect()).open(https_url(url), timeout=30)


def validate_manifest(data):
    if not isinstance(data, dict) or data.get('schema') != 2:
        raise Failure('A schema 2 release manifest is required.')
    if not isinstance(data.get('version'), str) or not data['version']:
        raise Failure('The release version is missing.')
    if type(data.get('versionCode')) is not int or data['versionCode'] < 1:
        raise Failure('The release versionCode is invalid.')
    if not isinstance(data.get('artifacts'), list) or not data['artifacts']:
        raise Failure('The release contains no artifacts.')
    names = set()
    for item in data['artifacts']:
        if not isinstance(item, dict) or item.get('type') not in KINDS:
            raise Failure('The release contains an unknown artifact type.')
        name = checked_word(item.get('name'), 'artifact name')
        if name in names:
            raise Failure(f'Duplicate artifact: {name}')
        names.add(name)
        if not re.fullmatch('[0-9a-f]{64}', str(item.get('sha256', ''))):
            raise Failure(f'Invalid SHA-256: {name}')
        if type(item.get('size')) is not int or not 0 < item['size'] <= 4 * 1024**3:
            raise Failure(f'Invalid artifact size: {name}')
        https_url(item.get('url', ''))
        for key in ('devices', 'abis', 'androidBuilds'):
            if key in item and (not isinstance(item[key], list) or not item[key] or
                                any(not isinstance(x, str) or not x for x in item[key])):
                raise Failure(f'Invalid {key}: {name}')
        if item.get('support', 'experimental') not in ('qualified', 'experimental'):
            raise Failure(f'Invalid support status: {name}')
        if item['type'] == 'rootfs' and item.get('distro') not in ('debian', 'arch', 'alpine'):
            raise Failure('Rootfs distro is missing or invalid.')
        if item['type'] == 'boot' and (not item.get('devices') or not item.get('androidBuilds')):
            raise Failure('Boot artifacts must pin a device and exact Android fingerprint.')
    return data


def select_artifacts(manifest, device, distro, experimental=True):
    selected = {}
    for kind in KINDS:
        matches = []
        for item in manifest['artifacts']:
            if item['type'] != kind or (kind == 'rootfs' and item['distro'] != distro):
                continue
            if item.get('devices') and not set(item['devices']) & set(device['devices']):
                continue
            if item.get('abis') and not set(item['abis']) & set(device['abis']):
                continue
            if item.get('androidBuilds') and device['fingerprint'] not in item['androidBuilds']:
                continue
            if item.get('support', 'experimental') != 'qualified' and not experimental:
                continue
            matches.append(item)
        if len(matches) != 1:
            raise Failure(f'{kind}: expected one compatible artifact, found {len(matches)}. '
                          'Select another release or build a port for this device.')
        selected[kind] = matches[0]
    return selected


def validate_archive(path, kind, distro='debian'):
    if kind == 'boot':
        with Path(path).open('rb') as stream:
            if stream.read(8) != b'ANDROID!':
                raise Failure('The boot image has invalid Android magic.')
        return 0
    if kind in ('module', 'companion'):
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            for name in names:
                if PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts:
                    raise Failure('The ZIP contains an unsafe path.')
            if kind == 'module':
                required = {'module.prop', 'customize.sh', 'tools/guest-distro', 'tools/desktop-on',
                            'zygisk/arm64-v8a.so', 'zygisk/armeabi-v7a.so'}
                if not required <= names or b'id=determination' not in archive.read('module.prop').splitlines():
                    raise Failure('The module is incomplete or has the wrong module ID.')
            elif 'AndroidManifest.xml' not in names:
                raise Failure('The companion APK has no Android manifest.')
            if archive.testzip():
                raise Failure('The ZIP failed its CRC check.')
        return 0
    total = 0
    with tarfile.open(path, 'r:gz') as archive:
        members = archive.getmembers()
        names = {}
        links = set()
        for member in members:
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or '\\' in member.name:
                raise Failure(f'Unsafe archive path: {member.name}')
            name = str(PurePosixPath(member.name))
            if name in names and name != '.':
                raise Failure(f'Duplicate archive member: {name}')
            names[name] = member
            total += member.size
            if total > 32 * 1024**3:
                raise Failure('The expanded archive exceeds 32 GiB.')
            if kind == 'runtime' and (name not in LXC_TOOLS or not member.isfile()):
                raise Failure('Runtime archives must contain only regular LXC executables.')
            if member.issym() or member.islnk():
                target = member.linkname
                if (member.islnk() and target.startswith('/')) or '\\' in target:
                    raise Failure(f'Absolute archive link: {name}')
                parent = PurePosixPath(name).parent if member.issym() else PurePosixPath('.')
                if target.startswith('/'):
                    target = target.lstrip('/')
                    parent = PurePosixPath('.')
                depth = 0
                for part in (parent / target).parts:
                    depth += -1 if part == '..' else 0 if part == '.' else 1
                    if depth < 0:
                        raise Failure(f'Archive link escapes root: {name}')
                links.add(name)
            if member.isdev() or member.isfifo():
                raise Failure(f'Special archive member is not supported: {name}')
        for name in names:
            if any(str(parent) in links for parent in PurePosixPath(name).parents):
                raise Failure(f'Archive writes through a link: {name}')
        if kind == 'runtime' and set(names) != LXC_TOOLS:
            raise Failure('The runtime is missing required LXC executables.')
        if kind == 'rootfs':
            identity = 'etc/os-release' if distro == 'debian' else 'etc/determination-profile'
            member = names.get(identity)
            if not member or not member.isfile() or member.size > 65536:
                raise Failure('The rootfs identity file is missing or invalid.')
            identity_text = archive.extractfile(member).read().decode('utf-8')
            if not re.search(rf'^ID=["\']?{re.escape(distro)}["\']?\s*$', identity_text, re.M):
                raise Failure('The rootfs does not match the selected distro.')
            if not {'sbin/init', 'bin/init'} & set(names):
                raise Failure('The rootfs contains no init.')
    return total


class Engine:
    def __init__(self, workspace, emit=lambda event: None, adb='adb', magiskboot='magiskboot'):
        self.workspace = Path(workspace).expanduser().resolve()
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.emit = emit
        self.adb = adb
        self.magiskboot = magiskboot
        self.serial = None
        self.cancel = threading.Event()
        self.protected = False
        self.log_path = self.workspace / 'operations.log'

    def log(self, message):
        message = str(message)
        with self.log_path.open('a') as stream:
            stream.write(message + '\n')
        self.emit({'log': message})

    def checkpoint(self):
        if self.cancel.is_set() and not self.protected:
            raise Cancelled('Operation stopped. Completed downloads and backups are retained.')

    def phase(self, name):
        self.checkpoint()
        self.emit({'phase': name})
        self.log(name)

    @contextlib.contextmanager
    def transaction(self):
        lock = self.workspace / 'operation.lock'
        try:
            descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError as exc:
            raise Failure(f'Workspace is busy. If its process has exited, remove {lock}.') from exc
        try:
            os.write(descriptor, str(os.getpid()).encode())
            os.close(descriptor)
            yield
        finally:
            lock.unlink(missing_ok=True)

    @contextlib.contextmanager
    def critical(self):
        previous = self.protected
        handler = None
        if threading.current_thread() is threading.main_thread():
            handler = signal.signal(signal.SIGINT, lambda *_: self.cancel.set())
        self.protected = True
        self.emit({'protected': True})
        try:
            yield
        finally:
            self.protected = previous
            self.emit({'protected': previous})
            if handler is not None:
                signal.signal(signal.SIGINT, handler)

    def fetch_source(self, url, ref, name):
        https_url(url)
        checked_word(name, 'source folder')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]{0,159}', ref) or '..' in ref:
            raise Failure('Select a valid kernel branch or tag.')
        target = self.workspace / 'sources' / name
        suffix = 2
        while target.exists():
            target = self.workspace / 'sources' / f'{name}-{suffix}'
            suffix += 1
        target.parent.mkdir(parents=True, exist_ok=True)
        self.phase('Downloading the downstream kernel source')
        try:
            self.run(['git', 'clone', '--depth=1', '--branch', ref, '--', url, target], timeout=1800)
        except BaseException:
            if target.exists():
                shutil.rmtree(target)
            raise
        return str(target)

    def extract_magiskboot(self, apk):
        if platform.system() != 'Linux':
            raise Failure('APK host tools require Linux or WSL2.')
        abi = {'x86_64': 'x86_64', 'aarch64': 'arm64-v8a'}.get(platform.machine())
        if not abi:
            raise Failure('This host CPU is not supported by the Magisk APK tool extractor.')
        name = f'lib/{abi}/libmagiskboot.so'
        with zipfile.ZipFile(apk) as archive:
            entry = archive.getinfo(name)
            if entry.file_size > 32 * 1024**2:
                raise Failure('The magiskboot executable is unexpectedly large.')
            data = archive.read(entry)
        if data[:4] != b'\x7fELF':
            raise Failure('The APK does not contain a Linux magiskboot executable.')
        target = self.workspace / 'tools/magiskboot'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755)
        self.log('Extracted host magiskboot from the selected APK: ' + str(target))
        return str(target)

    def run(self, args, cwd=None, env=None, timeout=120, acceptable=(0,)):
        self.checkpoint()
        args = [str(x) for x in args]
        self.log('$ ' + shlex.join(args))
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / 'output'
            output = log.open('wb')
            process = subprocess.Popen(args, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=(os.name == 'posix'))
            start, position = time.monotonic(), 0
            collected = bytearray()
            try:
                while True:
                    with log.open('rb') as reader:
                        reader.seek(position)
                        chunk = reader.read()
                    if chunk:
                        position += len(chunk)
                        collected.extend(chunk)
                        if len(collected) > 8 * 1024 * 1024:
                            del collected[:-8 * 1024 * 1024]
                        self.log(chunk.decode(errors='replace').rstrip())
                    if process.poll() is not None:
                        with log.open('rb') as reader:
                            reader.seek(position)
                            chunk = reader.read()
                        collected.extend(chunk)
                        if chunk:
                            self.log(chunk.decode(errors='replace').rstrip())
                        break
                    self.checkpoint()
                    if time.monotonic() - start > timeout:
                        raise Failure(f'Operation timed out after {timeout} seconds.')
                    time.sleep(0.1)
            except BaseException:
                if os.name == 'posix':
                    os.killpg(process.pid, signal.SIGTERM)
                else:
                    process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    if os.name == 'posix':
                        os.killpg(process.pid, signal.SIGKILL)
                    else:
                        process.kill()
                    process.wait()
                raise
            finally:
                output.close()
        result = collected.decode(errors='replace').strip()
        if process.returncode not in acceptable:
            raise Failure(f'Command failed ({process.returncode}): {args[0]}\n{result[-4000:]}')
        return result, process.returncode

    def adb_args(self, *args):
        if not self.serial:
            raise Failure('Select a device first.')
        return [self.adb, '-s', self.serial, *args]

    def shell(self, script, root=False, timeout=120):
        command = 'su -c ' + shlex.quote(script) if root else script
        return self.run(self.adb_args('shell', command), timeout=timeout)[0]

    def devices(self):
        output, _ = self.run([self.adb, 'devices', '-l'])
        return [{'serial': fields[0], 'state': fields[1], 'details': ' '.join(fields[2:])}
                for line in output.splitlines()[1:] if len(fields := line.split()) >= 2]

    def inspect(self, serial):
        if not any(x['serial'] == serial and x['state'] == 'device' for x in self.devices()):
            raise Failure('The selected device is offline or unauthorized. Authorize USB debugging on the phone.')
        self.serial = serial
        self.phase('Inspecting the selected device')
        if self.shell('id -u', root=True).strip() != '0':
            raise Failure('Grant root access to Shell in Magisk.')
        properties = self.shell('getprop')
        props = dict(re.findall(r'^\[([^\]]+)\]: \[(.*)\]$', properties, re.M))
        slot = props.get('ro.boot.slot_suffix', '')
        if slot not in ('', '_a', '_b'):
            raise Failure('Unrecognized boot slot suffix.')
        device = {
            'serial': serial, 'device': checked_word(props.get('ro.product.device'), 'device'),
            'devices': list(filter(None, {props.get(key, '') for key in (
                        'ro.product.device', 'ro.product.system.device', 'ro.product.vendor.device',
                        'ro.build.product', 'ro.crdroid.device', 'ro.boot.project_codename')})),
            'abis': props.get('ro.product.cpu.abilist', props.get('ro.product.cpu.abi', '')).split(','),
            'fingerprint': props.get('ro.build.fingerprint', ''), 'slot': slot,
            'model': props.get('ro.product.model', ''), 'kernel': self.shell('uname -r'),
        }
        if not device['fingerprint'] or 'arm64-v8a' not in device['abis']:
            raise Failure('A known Android fingerprint and arm64 device are required.')
        device['partitions'] = partitions(self.shell(PARTITIONS, root=True))
        boots = [p for p in device['partitions'] if p['name'] == 'boot' + slot]
        if len({p['node'] for p in boots}) != 1:
            raise Failure('The active boot partition could not be identified unambiguously.')
        device['part'], device['boot_size'] = boots[0]['path'], boots[0]['size']
        battery = self.shell('dumpsys battery')
        match = re.search(r'^\s*level:\s*(\d+)\s*$', battery, re.M)
        device['battery'] = int(match[1]) if match else 0
        device['properties'] = props
        device['probes'] = {}
        for name, script in PROBES.items():
            self.phase('Extracting device ' + name)
            try:
                output, status = self.run(self.adb_args('shell', 'su -c ' + shlex.quote(script)), timeout=45, acceptable=tuple(range(256)))
                device['probes'][name] = {'output': output, 'exitCode': status}
            except Cancelled:
                raise
            except Failure as error:
                device['probes'][name] = {'output': '', 'error': str(error)}
        config_probe = device['probes']['config']
        device['config'] = config_probe['output'] if config_probe.get('exitCode') == 0 else ''
        device['missing'] = [key for key in REQUIRED if f'CONFIG_{key}=y' not in device['config'].splitlines()]
        device['display'] = device['probes']['display']['output']
        device['graphics'] = device['probes']['graphics']['output']
        evidence = self.workspace / 'recon' / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]) / 'device.json'
        device['evidence'] = str(evidence)
        save_json(evidence, device)
        save_json(self.workspace / 'device.json', device)
        return device

    def assert_device(self, device):
        if self.serial != device['serial']:
            raise Failure('The selected serial changed.')
        fingerprint = self.shell('getprop ro.build.fingerprint')
        slot = self.shell('getprop ro.boot.slot_suffix')
        if fingerprint != device['fingerprint'] or slot != device['slot']:
            raise Failure('The device build or active slot changed. Inspect it again.')
        battery = self.shell('dumpsys battery')
        match = re.search(r'^\s*level:\s*(\d+)\s*$', battery, re.M)
        if not match or int(match[1]) < 20:
            raise Failure('Charge the phone to at least 20%; battery must be readable.')

    def load_manifest(self, source):
        self.phase('Reading the release manifest')
        if source.startswith('https://'):
            with open_https(source) as response:
                raw = response.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024:
                raise Failure('The manifest is too large.')
        else:
            raw = Path(source).expanduser().read_bytes()
        return validate_manifest(json.loads(raw))

    def download(self, item, local_dir=None):
        self.checkpoint()
        target = self.workspace / 'cache' / item['sha256'] / item['name']
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and target.stat().st_size == item['size'] and digest(target) == item['sha256']:
            self.log('Using verified cache: ' + item['name'])
            return target
        target.unlink(missing_ok=True)
        partial = target.with_suffix(target.suffix + '.partial')
        try:
            local = Path(local_dir) / item['name'] if local_dir else None
            source = local.open('rb') if local and local.is_file() else open_https(item['url'])
            with source, partial.open('wb') as output:
                received = 0
                while chunk := source.read(1024 * 1024):
                    self.checkpoint()
                    received += len(chunk)
                    if received > item['size']:
                        raise Failure('The download exceeds the declared size.')
                    output.write(chunk)
                    self.emit({'download': item['name'], 'received': received, 'total': item['size']})
            if partial.stat().st_size != item['size'] or digest(partial) != item['sha256']:
                raise Failure('Artifact size or SHA-256 does not match: ' + item['name'])
            partial.replace(target)
            return target
        finally:
            partial.unlink(missing_ok=True)

    def backup(self, device):
        self.assert_device(device)
        self.phase('Saving and verifying the boot backup on this PC')
        directory = self.workspace / 'backups' / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
        directory.mkdir(parents=True)
        target = directory / 'boot.img'
        expected = self.shell('sha256sum ' + device['part'], root=True).split()[0]
        with target.open('wb') as output:
            subprocess.run(self.adb_args('exec-out', 'su -c ' + shlex.quote('cat ' + device['part'])),
                           stdout=output, stderr=subprocess.PIPE, check=True, timeout=180)
            output.flush()
            os.fsync(output.fileno())
        if target.stat().st_size != device['boot_size'] or digest(target) != expected:
            raise Failure('The PC boot backup failed verification. No partition was written.')
        metadata = {key: device[key] for key in ('serial', 'device', 'fingerprint', 'slot', 'part', 'boot_size')}
        metadata['sha256'] = expected
        save_json(directory / 'backup.json', metadata)
        self.log(f'Verified recovery backup: {target}')
        return target

    def repack(self, backup, kernel=None, release_boot=None):
        self.phase('Repacking the device boot image on this PC')
        directory = self.workspace / 'build' / uuid.uuid4().hex
        directory.mkdir(parents=True)
        current = directory / 'current'
        current.mkdir()
        self.run([self.magiskboot, 'unpack', Path(backup).resolve()], cwd=current)
        ramdisk = current / 'ramdisk.cpio'
        if not ramdisk.is_file():
            raise Failure('This boot layout has no ramdisk. Separate init_boot packaging is not implemented.')
        self.run([self.magiskboot, 'cpio', ramdisk, 'test'], acceptable=(1,))
        ramdisk_hash = digest(ramdisk)
        if release_boot:
            candidate = directory / 'candidate'
            candidate.mkdir()
            self.run([self.magiskboot, 'unpack', Path(release_boot).resolve()], cwd=candidate)
            kernel = candidate / 'kernel'
        if not kernel or not Path(kernel).is_file():
            raise Failure('The build produced no kernel image.')
        shutil.copyfile(kernel, current / 'kernel')
        output = directory / 'determination-boot.img'
        self.run([self.magiskboot, 'repack', Path(backup).resolve(), output], cwd=current)
        validate_archive(output, 'boot')
        verify = directory / 'verify'
        verify.mkdir()
        self.run([self.magiskboot, 'unpack', output], cwd=verify)
        if digest(verify / 'ramdisk.cpio') != ramdisk_hash or digest(verify / 'kernel') != digest(current / 'kernel'):
            raise Failure('Repacked kernel or Magisk ramdisk verification failed.')
        return output

    def stage(self, path, remote):
        self.run(self.adb_args('push', Path(path).resolve(), remote), timeout=1800)
        if self.shell('sha256sum ' + shlex.quote(remote), root=True).split()[0] != digest(path):
            raise Failure('The device staging checksum failed.')

    def flash(self, device, image, backup):
        self.assert_device(device)
        validate_archive(image, 'boot')
        if Path(image).stat().st_size > device['boot_size']:
            raise Failure('The image exceeds the boot partition size.')
        metadata = json.loads(Path(backup).with_name('backup.json').read_text())
        if digest(backup) != metadata['sha256'] or any(metadata[k] != device[k] for k in ('serial', 'fingerprint', 'slot')):
            raise Failure('The recovery backup does not match the selected device.')
        remote = '/data/local/tmp/det-flash-' + uuid.uuid4().hex
        self.shell('mkdir -m 700 ' + remote)
        self.stage(image, remote + '/new.img')
        self.stage(backup, remote + '/backup.img')
        script = f'''set -eu
part={shlex.quote(device['part'])}
[ "$(getprop ro.boot.slot_suffix)" = {shlex.quote(device['slot'])} ]
[ "$(getprop ro.build.fingerprint)" = {shlex.quote(device['fingerprint'])} ]
[ "$(sha256sum "$part" | cut -d ' ' -f1)" = {metadata['sha256']} ]
restore() {{
    dd if={remote}/backup.img of="$part" bs=1048576 && sync || return 1
    [ "$(sha256sum "$part" | cut -d ' ' -f1)" = {metadata['sha256']} ]
}}
if dd if={remote}/new.img of="$part" bs=1048576 && sync &&
   [ "$(head -c {Path(image).stat().st_size} "$part" | sha256sum | cut -d ' ' -f1)" = {digest(image)} ]; then
    echo 'Boot write and readback verified.'
else
    restore && echo 'Original boot restored and verified.' || echo 'CRITICAL: Restore failed. Keep the PC backup and do not reboot.'
    exit 1
fi
'''
        self.phase('Writing and verifying boot; cancellation is temporarily disabled')
        with self.critical():
            self.shell(script, root=True, timeout=600)
        if not self.cancel.is_set():
            self.shell('rm -rf ' + remote)

    def device_profile(self, device):
        text = ''.join(f'{key}={value}\n' for key, value in profile_values(device).items())
        output = self.workspace / 'ports' / device['device'] / 'device.conf'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text)
        return output

    def port(self, device, source, target, jobs, bundle_source, distro, make_args=''):
        self.assert_device(device)
        source = Path(source).expanduser().resolve()
        if not (source / 'Makefile').is_file() or not (source / 'scripts/kconfig/merge_config.sh').is_file():
            raise Failure('Select the downstream kernel source directory with Makefile and merge_config.sh.')
        if target not in ('Image', 'Image.gz', 'Image.gz-dtb'):
            raise Failure('Unsupported kernel image target.')
        if not 1 <= int(jobs) <= 256:
            raise Failure('Build jobs must be between 1 and 256.')
        arguments = shlex.split(make_args)
        for arg in arguments:
            if not re.fullmatch(r'(CC|LD|AR|NM|OBJCOPY|OBJDUMP|STRIP|CROSS_COMPILE|CROSS_COMPILE_ARM32|LLVM|LLVM_IAS)=[A-Za-z0-9_./+-]+', arg):
                raise Failure('Toolchain overrides must be explicit compiler or LLVM make assignments.')
        profile = self.device_profile(device)
        output = profile.parent / 'kernel'
        output.mkdir(exist_ok=True)
        base = profile.parent / 'running.config'
        if not re.search(r'^CONFIG_ARM64=y$', device.get('config', ''), re.M):
            raise Failure('Provide the matching running kernel configuration with CONFIG_ARM64=y.')
        base.write_text(device['config'])
        source_commit, _ = self.run(['git', '-C', source, 'rev-parse', 'HEAD'])
        source_changes, _ = self.run(['git', '-C', source, 'status', '--porcelain'])
        overlay = profile.parent / 'determination.config'
        overlay.write_text('\n'.join(line for line in (REPO / 'kernel/determination.config').read_text().splitlines()
                                     if line.startswith('CONFIG_')) + '\n# CONFIG_FRAMEBUFFER_CONSOLE is not set\n')
        config = output / '.config'
        shutil.copyfile(base, config)
        fragments = [str(overlay)]
        env = dict(os.environ, KCONFIG_CONFIG=str(config))
        self.phase('Applying Determination kernel requirements to the running device configuration')
        self.run(['sh', source / 'scripts/kconfig/merge_config.sh', '-m', '-O', output, config, *fragments], cwd=source, env=env)
        make = ['make', '-C', source, f'O={output}', 'ARCH=arm64', 'LLVM=1', 'LLVM_IAS=1', *arguments]
        self.run([*make, 'olddefconfig'], timeout=300)
        configured = config.read_text().splitlines()
        missing = [key for key in REQUIRED if f'CONFIG_{key}=y' not in configured]
        if missing or 'CONFIG_FRAMEBUFFER_CONSOLE=y' in configured:
            raise Failure('Kernel configuration cannot satisfy the container contract: ' + ', '.join(missing or ['FRAMEBUFFER_CONSOLE must be disabled']))
        self.phase('Building the ported downstream kernel')
        self.run([*make, f'-j{jobs}', target], timeout=14400)
        kernel = output / 'arch/arm64/boot' / target
        if not kernel.is_file():
            raise Failure(f'The build did not produce the requested arm64 kernel: {target}.')
        backup = self.backup(device)
        boot = self.repack(backup, kernel=kernel)
        self.phase('Assembling the device installation bundle')
        manifest = self.load_manifest(bundle_source)
        local_dir = Path(bundle_source).expanduser().resolve().parent if not bundle_source.startswith('https://') else None
        bundle = profile.parent / ('bundle-' + uuid.uuid4().hex[:8])
        bundle.mkdir()
        artifacts = []
        for kind in ('module', 'runtime', 'rootfs', 'companion'):
            candidates = [a for a in manifest['artifacts'] if a['type'] == kind and
                          (kind != 'rootfs' or a['distro'] == distro) and
                          (not a.get('abis') or set(a['abis']) & set(device['abis']))]
            if len(candidates) != 1:
                raise Failure(f'Select a base bundle containing one {kind} for {distro}.')
            artifact = dict(candidates[0])
            path = self.download(artifact, local_dir)
            validate_archive(path, kind, distro)
            destination = bundle / artifact['name']
            if kind == 'module':
                with zipfile.ZipFile(path) as original, zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as adapted:
                    for entry in original.infolist():
                        if entry.filename.startswith('device-profiles/'):
                            continue
                        adapted.writestr(entry, original.read(entry))
                    adapted.write(profile, 'device-profiles/' + device['device'] + '.conf')
            else:
                shutil.copyfile(path, destination)
            artifact.update(devices=device['devices'], androidBuilds=[device['fingerprint']], support='experimental',
                            sha256=digest(destination), size=destination.stat().st_size)
            artifacts.append(artifact)
        destination = bundle / 'determination-boot.img'
        shutil.copyfile(boot, destination)
        artifacts.append(dict(type='boot', name=destination.name, url='https://localhost/' + destination.name,
                              devices=device['devices'], androidBuilds=[device['fingerprint']], abis=['arm64-v8a'],
                              support='experimental', sha256=digest(destination), size=destination.stat().st_size))
        manifest['artifacts'] = artifacts
        save_json(bundle / 'determination-update.json', validate_manifest(manifest))
        save_json(bundle / 'device-evidence.json', device)
        save_json(bundle / 'port-build.json', {'device': device['device'], 'fingerprint': device['fingerprint'],
                  'source': str(source), 'sourceCommit': source_commit, 'sourceDirty': bool(source_changes), 'target': target, 'configSha256': digest(config), 'kernelSha256': digest(kernel),
                  'qualification': 'experimental', 'backup': str(backup)})
        self.log('Built installable port: ' + str(bundle))
        return str(bundle / 'determination-update.json')

    def install(self, device, source, distro, hostname, experimental=True, prepare_only=False,
                display_name='Determination User'):
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', hostname):
            raise Failure('Hostname must contain lowercase letters, digits, and internal hyphens.')
        display_name = display_name_value(display_name)
        self.assert_device(device)
        manifest = self.load_manifest(source)
        artifacts = select_artifacts(manifest, device, distro, experimental)
        local_dir = Path(source).expanduser().resolve().parent if not source.startswith('https://') else None
        files, expanded = {}, 0
        self.phase('Downloading and validating the complete installation bundle')
        for kind, artifact in artifacts.items():
            files[kind] = self.download(artifact, local_dir)
            expanded += validate_archive(files[kind], kind, distro)
        with zipfile.ZipFile(files['module']) as module:
            properties = module.read('module.prop').decode('utf-8')
        if not re.search(rf'^versionCode={manifest["versionCode"]}\s*$', properties, re.M):
            raise Failure('The module versionCode does not match the release manifest.')
        backup = self.backup(device)
        image = self.repack(backup, release_boot=files['boot'])
        if image.stat().st_size > device['boot_size']:
            raise Failure('The repacked boot image does not fit.')
        plan = {'device': device['device'], 'serial': device['serial'], 'fingerprint': device['fingerprint'],
                'version': manifest['version'], 'distro': distro, 'hostname': hostname,
                'displayName': display_name,
                'backup': str(backup), 'image': str(image), 'artifacts': artifacts, 'status': 'prepared'}
        save_json(self.workspace / 'installation.json', plan)
        if prepare_only:
            self.log('Preparation complete. Downloads, repacked boot, and PC backup are verified. Nothing installed.')
            return plan
        free = int(self.shell("df -Pk /data | tail -n 1 | awk '{print $4}'", root=True)) * 1024
        needed = expanded + sum(a['size'] for a in artifacts.values()) + device['boot_size'] * 3 + 512 * 1024**2
        if free < needed:
            raise Failure(f'Insufficient phone storage: require {needed // 1024**2} MiB free.')
        self.shell('set -e; test ! -f /data/determination/run/desktop-mode; '
                   'if [ -x /data/determination/lxc/bin/lxc-info ]; then '
                   'state=$(/data/determination/lxc/bin/lxc-info -P /data/determination -n guest -sH) || exit 1; [ "$state" = STOPPED ]; fi', root=True)
        remote = '/data/local/tmp/det-install-' + uuid.uuid4().hex
        self.shell('mkdir -m 700 ' + remote)
        completed = False
        try:
            for kind, path in files.items():
                self.phase('Staging ' + kind)
                self.stage(path, remote + '/' + kind)
            self.phase('Installing the root integration, runtime, and guest')
            script = (REPO / 'installer/install-device.sh').read_text()
            script = 'set -- ' + shlex.join(
                [remote, distro, hostname, str(manifest['versionCode']), display_name]
            ) + '\n' + script
            with self.critical():
                self.shell(script, root=True, timeout=3600)
            self.phase('Installing the companion controller')
            self.run(self.adb_args('install', '-r', files['companion']), timeout=300)
            plan['status'] = 'userspace-installed'
            save_json(self.workspace / 'installation.json', plan)
            self.flash(device, image, backup)
            plan['status'] = 'installed-reboot-required'
            save_json(self.workspace / 'installation.json', plan)
            completed = True
            self.log('Installation complete. Reboot from Recovery, then run Verify installation.')
            return plan
        except BaseException:
            plan['status'] = 'incomplete'
            save_json(self.workspace / 'installation.json', plan)
            raise
        finally:
            if completed and not self.cancel.is_set():
                try:
                    self.shell('rm -rf ' + remote)
                except Exception as error:
                    self.log(f'Staging cleanup failed: {error}')

    def verify(self, device):
        self.assert_device(device)
        config = self.shell('zcat /proc/config.gz', root=True).splitlines()
        missing = [key for key in REQUIRED if f'CONFIG_{key}=y' not in config]
        if missing:
            raise Failure('Running kernel is missing: ' + ', '.join(missing))
        self.shell('test -x /data/determination/bin/desktop-on && '
                   'test -x /data/determination/lxc/bin/lxc-start && '
                   'test -f /data/determination/active-guest/etc/os-release && '
                   'test -d /data/adb/modules/determination && '
                   'test ! -f /data/adb/modules/determination/disable', root=True)
        self.log('Kernel, module, runtime, and guest installation checks passed. Graphics qualification is separate.')

    def restore(self, device, backup):
        metadata = json.loads(Path(backup).with_name('backup.json').read_text())
        if any(metadata[key] != device[key] for key in ('serial', 'fingerprint', 'slot', 'boot_size')) or digest(backup) != metadata['sha256']:
            raise Failure('This backup does not match the device, build, slot, or checksum.')
        current = self.backup(device)
        self.flash(device, Path(backup), current)
        self.log('Boot backup restored and verified. Guest data and module files are retained.')
