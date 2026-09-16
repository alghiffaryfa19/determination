#!/usr/bin/env python3
"""Fetch and authenticate the upstream base using an isolated signing keyring."""
import argparse
import os
from pathlib import Path
import subprocess
import urllib.request

KEY = '68B3537F39A313B3E574D06777193F152BDBE6A6'
URL = 'https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz'


def fetch(url, destination):
    if destination.is_file():
        return
    temporary = destination.with_suffix(destination.suffix + '.partial')
    with urllib.request.urlopen(url, timeout=60) as response, temporary.open('wb') as output:
        if not response.url.startswith('https://'):
            raise RuntimeError('Refusing an insecure download redirect')
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
    temporary.replace(destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('work', type=Path)
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    keyring = work / 'gnupg'
    keyring.mkdir(mode=0o700, exist_ok=True)
    keyfile = work / 'archlinuxarm.gpg'
    fetch('https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x' + KEY, keyfile)
    gpg = ['gpg', '--homedir', str(keyring), '--batch', '--no-autostart']
    subprocess.run([*gpg, '--import', keyfile], check=True)
    source = args.source.resolve() if args.source else work / 'ArchLinuxARM-aarch64.tar.gz'
    if not args.source:
        fetch(URL, source)
        fetch(URL + '.sig', Path(str(source) + '.sig'))
    status = subprocess.check_output([*gpg, '--status-fd', '1', '--verify', str(source) + '.sig', source], text=True)
    if not any(line.startswith('[GNUPG:] VALIDSIG ') and KEY in (line.split()[2], line.split()[-1])
               for line in status.splitlines()):
        raise RuntimeError('Arch base archive was not signed by the pinned upstream key')
    env = dict(os.environ, GNUPGHOME=str(keyring), OUT=str(work / 'base.tar.gz'))
    subprocess.run(['sh', str(Path(__file__).with_name('build-portable-rootfs.sh')), 'arch', str(source)],
                   env=env, check=True)


if __name__ == '__main__':
    main()
