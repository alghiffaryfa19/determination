from __future__ import annotations

import os
from pathlib import Path
import platform
import shutil
import subprocess

from core import Failure, REPO
from pipeline import Pipeline, Stage


def doctor(workspace):
    checks = []
    def add(name, ok, detail):
        checks.append({'id': name, 'ok': bool(ok), 'detail': detail})
    add('host', platform.system() == 'Linux', 'Linux is required for the rootless container build.')
    add('architecture', platform.machine() in ('x86_64', 'aarch64'), 'Supported build hosts: x86_64, aarch64.')
    podman = shutil.which('podman')
    add('podman', podman, 'Install Podman and configure rootless user namespaces.')
    if podman:
        try:
            result = subprocess.run([podman, 'info', '--format', '{{.Host.Security.Rootless}}'],
                                    capture_output=True, text=True, timeout=30)
            add('containers', result.returncode == 0, result.stderr.strip() or 'Container runtime responds.')
        except (OSError, subprocess.TimeoutExpired) as exc:
            add('containers', False, str(exc))
    parent = Path(workspace).expanduser().resolve()
    while not parent.exists():
        parent = parent.parent
    free = shutil.disk_usage(parent).free
    add('disk', free >= 20 * 1024**3, f'{free // 1024**3} GiB free; reserve at least 20 GiB for the Arch build.')
    return {'schema': 1, 'ok': all(c['ok'] for c in checks), 'checks': checks}


def pipeline(engine, repo=REPO, jobs=6):
    repo = Path(repo).resolve()
    build = engine.workspace / 'builds/arch/work'
    image = 'localhost/aurora/arch-desktop-cross:trixie'
    guest = repo / 'guest'
    sources = (guest / 'sources.lock',)
    def container(script, *args):
        return ('podman', 'run', '--rm', '-v', f'{repo}:/work:ro', '-v', f'{build}:/build',
                '-e', 'AURORA_BUILD_ROOT=/build', '-e', 'AURORA_ARCH_BASE=/build/source/base.tar.gz',
                '-e', f'AURORA_BUILD_JOBS={jobs}', '-w', '/work', image, *script, *args)
    root = build / 'arch-desktop/sysroot'
    stages = [
        Stage('toolchain', 'Preparing the isolated cross toolchain',
              (guest / 'Containerfile.arch-desktop',), (build / 'toolchain.id',),
              ('podman', 'build', '--iidfile', str(build / 'toolchain.id'), '-t', image,
               '-f', str(guest / 'Containerfile.arch-desktop'), str(repo))),
        Stage('source', 'Authenticating the Arch Linux ARM base',
              (guest / 'prepare-arch-source.py', guest / 'build-portable-rootfs.sh',
               guest / 'customize-portable-rootfs.sh', guest / 'aurora-platform',
               guest / 'aurora-apps', guest / 'setup-compatibility.sh', *sources), (build / 'source/base.tar.gz',),
              container(('python3', '/work/guest/prepare-arch-source.py'), '/build/source'), ('toolchain',)),
        Stage('packages', 'Staging signed ARM64 desktop packages',
              (guest / 'prepare-arch-sysroot.sh', guest / 'aurora-apps'),
              (root / 'usr/lib/libc.so.6', root / 'usr/bin/phosh'),
              container(('sh', '/work/guest/prepare-arch-sysroot.sh')), ('source',)),
        Stage('graphics', 'Cross-building vendor EGL and the hwcomposer desktop',
              (*sources, *(guest / name for name in ('build-arch-desktop.sh', 'arch-desktop-cross.ini',
                   'build-libhybris.sh', 'build-wlroots-phoc.sh'))),
              (root / 'usr/local/bin/phoc', root / 'usr/local/lib/libEGL.so.1',
               root / 'usr/local/lib/libwlroots.so.12a'),
              container(('sh', '/work/guest/build-arch-desktop.sh'), '--inside'), ('packages',)),
        Stage('init', 'Cross-building the kernel-compatible init system',
              (guest / 'build-arch-systemd.sh', guest / 'arch-systemd-cross.ini'),
              (build / 'arch-systemd/install/usr/lib/systemd/systemd',
               build / 'arch-systemd/install/usr/lib/systemd/libsystemd-shared-257.so',
               build / 'arch-systemd/install/opt/hyprland/lib/compat/libudev.so.1'),
              ('sh', str(guest / 'build-arch-systemd.sh')), ('packages',)),
        Stage('rootfs', 'Assembling the installed application and graphics rootfs',
              (guest / 'assemble-arch-rootfs.sh', guest / 'customize-portable-rootfs.sh',
               guest / 'aurora-apps', guest / 'aurora-platform'),
              (build / 'aurora-rootfs-arch.tar.gz',),
              container(('sh', '/work/guest/assemble-arch-rootfs.sh')), ('graphics', 'init')),
    ]
    return Pipeline(engine, 'arch', stages, {'jobs': jobs}), build, image


def run(engine, repo=REPO, jobs=6):
    requirements = doctor(engine.workspace)
    if not requirements['ok']:
        raise Failure('Build prerequisites missing: ' + '; '.join(c['detail'] for c in requirements['checks'] if not c['ok']))
    recipe, build, image = pipeline(engine, repo, jobs)
    build.mkdir(parents=True, exist_ok=True)
    if subprocess.run(['podman', 'image', 'exists', image]).returncode:
        recipe.state['stages'].pop('toolchain', None)
    env = dict(os.environ, AURORA_BUILD_ROOT=str(build), AURORA_ARCH_BUILD_IMAGE=image,
               AURORA_BUILD_JOBS=str(jobs))
    return recipe.run(cwd=repo, env=env)
