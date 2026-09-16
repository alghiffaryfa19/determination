#!/usr/bin/env python3
"""Keep the compositor's name and installation prefix stable."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
retired = 'aurora' + 'hyprland'
for directory in ('guest', 'graphics', 'companion/app/src', 'tools'):
    for path in (ROOT / directory).rglob('*'):
        if any(part in ('vendor', 'build', '__pycache__', '.git') for part in path.parts):
            continue
        assert retired not in path.name.lower(), f'Retired filename: {path}'
        if not path.is_file() or path.stat().st_size > 1_000_000:
            continue
        try:
            text = path.read_text()
        except UnicodeError:
            continue
        # Captured historical evidence keeps its original filename.
        text = re.sub(r'artifacts/[^\s`]+', '', text)
        assert retired not in text.lower(), f'Retired compositor branding: {path}'
manifest = (ROOT / 'guest/sessions/hyprland.session').read_text()
assert 'title=Hyprland\n' in manifest
assert 'required_binaries=/opt/hyprland/bin/Hyprland,' in manifest
assert (ROOT / 'graphics/hyprland/HybrisBuffer.cpp').is_file()
assert (ROOT / 'guest/build-hyprland.sh').is_file()

# A config that loads a plugin the repository does not build makes Hyprland
# reload its configuration in a tight loop, which starves and kills the shell.
for config in sorted((ROOT / 'guest').glob('hyprland-*.conf')):
    for line in config.read_text().splitlines():
        if not line.startswith('plugin = '):
            continue
        binary = Path(line.split('=', 1)[1].strip()).name
        provided = any(path.name == binary for path in (ROOT / 'guest').rglob(binary))
        assert provided, f'{config.name} loads {binary} but nothing in the tree ships it'

print('Hyprland naming contract passed')
