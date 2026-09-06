#!/usr/bin/env python3
"""Host-only build profile regression tests; no compiler or phone required."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BUILD = Path(__file__).resolve().with_name('build.sh')


class BuildProfiles(unittest.TestCase):
    def test_profiles(self):
        for device, version, target in [('garnet', '5', 'Image'),
                                        ('generic', '5', 'Image'),
                                        ('guacamoleb', '4', 'Image.gz-dtb')]:
            with self.subTest(device=device), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                src = root / 'src'
                scripts = src / 'scripts/kconfig'
                scripts.mkdir(parents=True)
                (src / 'Makefile').write_text(f'VERSION = {version}\nPATCHLEVEL = 14\n')
                merge = scripts / 'merge_config.sh'
                merge.write_text('#!/bin/sh\nshift 4\nfor fragment do cat "$fragment" >> "$KCONFIG_CONFIG"; done\n')
                merge.chmod(0o755)
                make = root / 'make'
                make.write_text('''#!/bin/sh
for arg do
    case "$arg" in O=*) out=${arg#O=} ;; Image*) target=$arg ;; esac
done
if [ -n "$target" ]; then
    mkdir -p "$out/arch/arm64/boot"
    echo kernel > "$out/arch/arm64/boot/$target"
fi
''')
                make.chmod(0o755)
                base = root / 'base.config'
                base.write_text('CONFIG_QCA_CLD_WLAN=m\n')
                out = root / 'out'
                env = dict(os.environ, DEVICE=device, SRC=str(src), OUT=str(out),
                           BASECONFIG=str(base), PATH=f'{root}:/usr/bin:/bin')
                env.pop('KERNEL_TARGET', None)
                result = subprocess.run(['sh', str(BUILD)], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((out / 'kernel-image.path').read_text().strip(),
                                 str(out / 'arch/arm64/boot' / target))
                config = (out / '.config').read_text()
                self.assertEqual('CONFIG_QCA_CLD_WLAN=y' in config, device == 'guacamoleb')

    def test_garnet_requires_own_config(self):
        env = dict(os.environ, DEVICE='garnet')
        env.pop('BASECONFIG', None)
        result = subprocess.run(['sh', str(BUILD)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('BASECONFIG', result.stderr)


if __name__ == '__main__':
    unittest.main()
