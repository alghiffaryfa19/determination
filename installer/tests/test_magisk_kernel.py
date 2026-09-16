from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import Engine, Failure


class MagiskKernelTests(unittest.TestCase):
    def test_preserves_patch_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            kernel = Path(tmp) / 'kernel'
            kernel.write_bytes(b'prefix\0skip_initramfs\0suffix')
            Engine.preserve_legacy_sar(kernel)
            self.assertEqual(kernel.read_bytes(), b'prefix\0want_initramfs\0suffix')
            Engine.preserve_legacy_sar(kernel)
            self.assertEqual(kernel.read_bytes(), b'prefix\0want_initramfs\0suffix')

    def test_missing_marker_fails_without_modifying_kernel(self):
        with tempfile.TemporaryDirectory() as tmp:
            kernel = Path(tmp) / 'kernel'
            kernel.write_bytes(b'unknown kernel')
            with self.assertRaises(Failure):
                Engine.preserve_legacy_sar(kernel)
            self.assertEqual(kernel.read_bytes(), b'unknown kernel')


class RepackMagiskTests(unittest.TestCase):
    def test_repack_preserves_legacy_sar_for_built_and_release_kernels(self):
        for release in (False, True):
            with self.subTest(release=release), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                engine = Engine(root)
                backup = root / 'backup.img'
                backup.write_bytes(b'ANDROID!backup')
                replacement = root / 'Image'
                replacement.write_bytes(b'new-kernel\0skip_initramfs\0')
                packed = {}
                def run(args, cwd=None, **kwargs):
                    cwd = Path(cwd) if cwd is not None else root
                    if args[1] == 'unpack':
                        if cwd.name == 'current':
                            files = {'kernel': b'old-kernel\0want_initramfs\0',
                                     'ramdisk.cpio': b'Magisk ramdisk'}
                        elif cwd.name == 'candidate':
                            files = {'kernel': replacement.read_bytes()}
                        else:
                            files = packed
                        for name, data in files.items():
                            (cwd / name).write_bytes(data)
                    elif args[1] == 'cpio':
                        self.assertEqual(kwargs['acceptable'], (1,))
                    elif args[1] == 'repack':
                        packed.update({f.name: f.read_bytes() for f in cwd.iterdir()})
                        Path(args[3]).write_bytes(b'ANDROID!repacked')
                    else:
                        self.fail(str(args))
                    return '', 0
                with patch.object(engine, 'run', side_effect=run):
                    engine.repack(backup, **({'release_boot': replacement} if release else {'kernel': replacement}))
                self.assertEqual(packed['kernel'], b'new-kernel\0want_initramfs\0')
                self.assertEqual(packed['ramdisk.cpio'], b'Magisk ramdisk')
