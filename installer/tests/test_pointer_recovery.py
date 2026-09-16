import pathlib
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]


class PointerRecoveryTests(unittest.TestCase):
    def recover(self, root):
        source = (REPO / 'installer/install-device.sh').read_text()
        block = source.split('# Older module installers', 1)[1].split(
            '"$AURORA/bin/guest-distro" activate', 1)[0]
        return subprocess.run(['sh', '-eu', '-c', 'AURORA=$1\n# Older module installers' + block,
                               'recovery', str(root)], capture_output=True, text=True)

    def test_preserves_misplaced_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            assets = root / 'active-guest/etc/aurora'
            assets.mkdir(parents=True)
            (assets / 'settings.conf').write_text('preserve me')
            result = self.recover(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / 'active-guest').exists())
            saved, = root.glob('active-guest.saved.*')
            self.assertEqual((saved / 'etc/aurora/settings.conf').read_text(), 'preserve me')

    def test_refuses_real_rootfs_even_with_dangling_init(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / 'active-guest/sbin').mkdir(parents=True)
            (root / 'active-guest/sbin/init').symlink_to('/missing-init')
            self.assertNotEqual(self.recover(root).returncode, 0)
            self.assertTrue((root / 'active-guest').is_dir())
            self.assertEqual(list(root.glob('active-guest.saved.*')), [])

    def test_preserves_existing_pointer(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / 'active-guest').symlink_to('guests/arch/rootfs')
            self.assertEqual(self.recover(root).returncode, 0)
            self.assertEqual((root / 'active-guest').readlink(), pathlib.Path('guests/arch/rootfs'))

    def test_fresh_module_does_not_resolve_missing_pointer(self):
        source = (REPO / 'magisk-module/customize.sh').read_text()
        block = source.split('GUEST_ROOT=\n', 1)[1].split('# Retire', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(['sh', '-c', 'AURORA=$1\nGUEST_ROOT=\n' + block + '\nprintf "%s" "$GUEST_ROOT"',
                                     'module', tmp], capture_output=True, text=True)
            self.assertEqual(result.stdout, tmp + '/guest')


class GuestStoppedTests(unittest.TestCase):
    def test_partial_install_and_running_guest(self):
        source = (REPO / 'installer/install-device.sh').read_text()
        block = 'if [ -x "$AURORA/lxc/bin/lxc-info" ]; then' + source.split(
            'if [ -x "$AURORA/lxc/bin/lxc-info" ]; then', 1)[1].split(
            'if [ -d "$AURORA/versions/$version" ]; then', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            tools = root / 'lxc/bin'
            tools.mkdir(parents=True)
            info = tools / 'lxc-info'
            info.write_text('#!/bin/sh\necho "guest does not exist" >&2\nexit 1\n')
            info.chmod(0o755)
            listing = tools / 'lxc-ls'
            listing.write_text('#!/bin/sh\nexit 0\n')
            listing.chmod(0o755)
            def check():
                return subprocess.run(['sh', '-eu', '-c', 'AURORA=$1\n' + block,
                                       'check', tmp], capture_output=True)
            self.assertEqual(check().returncode, 0)
            listing.write_text('#!/bin/sh\necho guest\n')
            self.assertNotEqual(check().returncode, 0)
            listing.write_text('#!/bin/sh\nexit 1\n')
            self.assertNotEqual(check().returncode, 0)
            (root / 'guest').mkdir()
            (root / 'guest/config').touch()
            self.assertNotEqual(check().returncode, 0)
            info.write_text('#!/bin/sh\necho STOPPED\n')
            self.assertEqual(check().returncode, 0)
            info.write_text('#!/bin/sh\necho RUNNING\n')
            self.assertNotEqual(check().returncode, 0)
