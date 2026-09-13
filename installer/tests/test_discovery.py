import sys
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from discovery import partitions, profile_values
from core import Engine


class DiscoveryTests(unittest.TestCase):
    def test_inspection_keeps_evidence_when_config_is_unavailable(self):
        props = '[ro.product.device]: [otherphone]\n[ro.product.cpu.abi]: [arm64-v8a]\n[ro.build.fingerprint]: [vendor/build]\n[ro.boot.slot_suffix]: [_b]'
        with tempfile.TemporaryDirectory() as directory:
            engine = Engine(directory)
            with patch.object(engine, 'devices', return_value=[{'serial': 'usb', 'state': 'device'}]), \
                 patch.object(engine, 'shell', side_effect=['0', props, '6.1', 'boot_b|/dev/block/by-name/boot_b|/dev/block/sdc9|8192', 'level: 80']), \
                 patch.object(engine, 'run', return_value=('probe unavailable', 1)):
                data = engine.inspect('usb')
            self.assertEqual(data['part'], '/dev/block/by-name/boot_b')
            self.assertEqual(data['boot_size'], 8192)
            self.assertEqual(data['config'], '')
            self.assertTrue(Path(data['evidence']).is_file())
            self.assertEqual(data['probes']['input']['exitCode'], 1)

    def test_partition_paths_are_validated(self):
        rows = partitions('boot_a|/dev/block/by-name/boot_a|/dev/block/sda7|4096\nboot_a|/dev/block/x;reboot|/dev/block/sda7|4096')
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['node'], '/dev/block/sda7')

    def test_reference_name_does_not_supply_hardware_values(self):
        data = {'device': 'guacamoleb', 'display': 'Physical size: 1440x3200', 'probes': {
            'wireless': {'output': 'wifi2'}, 'drm': {'output': '/dev/dri/card2\n/dev/dri/renderD130'},
            'backlights': {'output': '/sys/class/backlight/my-panel|4095'}}}
        profile = profile_values(data)
        self.assertEqual(profile['DET_PANEL_HEIGHT'], '3200')
        self.assertEqual(profile['DET_WIFI_IFACE'], 'wifi2')
        self.assertEqual(profile['DET_DRM_CARD'], '/dev/dri/card2')
        self.assertEqual(profile['DET_BACKLIGHT_PATH'], '/sys/class/backlight/my-panel/brightness')
        self.assertNotIn('DET_BATTERY_GAUGE', profile)
        self.assertNotIn('DET_INPUT_QUIRK', profile)

    def test_ambiguous_hardware_is_not_selected(self):
        profile = profile_values({'device': 'phone', 'probes': {
            'wireless': {'output': 'wifi0\nwifi1'},
            'drm': {'output': '/dev/dri/card0\n/dev/dri/card1'}}})
        self.assertNotIn('DET_WIFI_IFACE', profile)
        self.assertNotIn('DET_DRM_CARD', profile)
