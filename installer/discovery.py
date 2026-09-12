import re


PROBES = {
    'config': 'zcat /proc/config.gz',
    'kernel': 'uname -a; cat /proc/version /proc/cmdline; cat /proc/bootconfig',
    'hardware': 'cat /proc/cpuinfo /proc/meminfo; for f in /sys/firmware/devicetree/base/model /sys/firmware/devicetree/base/compatible; do echo "$f"; tr "\\000" "\\n" < "$f"; done',
    'modules': 'cat /proc/modules; for d in /vendor/lib/modules /vendor_dlkm/lib/modules /system_dlkm/lib/modules; do ls -l "$d"; for f in "$d"/modules.load "$d"/modules.dep "$d"/modules.alias; do echo "$f"; head -c 262144 "$f"; done; done',
    'graphics': 'lshal; service list; ls -l /vendor/lib64/egl /vendor/lib64/hw /dev/dri /dev/dma_heap /dev/kgsl* /dev/mali* /dev/ion /dev/*binder*',
    'vintf': 'for f in /vendor/etc/vintf/manifest.xml /vendor/etc/vintf/manifest/*.xml /odm/etc/vintf/manifest.xml /odm/etc/vintf/manifest/*.xml; do [ -f "$f" ] || continue; echo "$f"; head -c 65536 "$f"; done',
    'display': 'wm size; wm density; dumpsys display; for f in /sys/class/drm/*/status /sys/class/drm/*/modes; do echo "$f"; cat "$f"; done',
    'input': 'cat /proc/bus/input/devices; getevent -lp',
    'power': 'for d in /sys/class/power_supply/*; do [ -d "$d" ] || continue; echo "$d"; cat "$d/uevent"; done',
    'backlights': 'for d in /sys/class/backlight/*; do [ -d "$d" ] || continue; printf "%s|" "$d"; cat "$d/max_brightness"; done',
    'thermal': 'for d in /sys/class/thermal/thermal_zone*; do echo "$d"; cat "$d/type" "$d/temp"; done',
    'network': 'ip link; ip route; for d in /sys/class/net/*; do [ -d "$d/wireless" ] && basename "$d"; done',
    'wireless': 'for d in /sys/class/net/*; do [ -d "$d/wireless" ] && basename "$d"; done',
    'audio': 'cat /proc/asound/cards /proc/asound/pcm',
    'drm': 'for f in /dev/dri/card* /dev/dri/renderD*; do [ -e "$f" ] && echo "$f"; done',
}

PARTITIONS = '''for d in /dev/block/by-name /dev/block/bootdevice/by-name /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name; do
    [ -d "$d" ] || continue
    for p in "$d"/*; do
        n=${p##*/}
        case "$n" in boot|boot_a|boot_b|init_boot*|vendor_boot*|recovery*|dtbo*|vbmeta*|vendor_dlkm*|system_dlkm*|super) ;;
        *) continue;; esac
        [ -b "$p" ] || continue
        printf '%s|%s|%s|' "$n" "$p" "$(readlink -f "$p")"
        blockdev --getsize64 "$p"
    done
done'''


def partitions(text):
    result = []
    for line in text.splitlines():
        fields = line.split('|')
        if len(fields) != 4:
            continue
        name, path, node, size = fields
        if not all(re.fullmatch(r'/dev/block/[A-Za-z0-9_./-]+', p) for p in (path, node)) or not size.isdigit():
            continue
        if int(size) > 0:
            result.append(dict(name=name, path=path, node=node, size=int(size)))
    return result


def profile_values(device):
    values = {'AURORA_PROFILE_ID': device['device'], 'AURORA_GRAPHICS_RENDERER': 'libhybris', 'AURORA_GBM_PROVIDER': 'minigbm'}
    probes = device.get('probes', {})
    def output(name):
        return probes.get(name, {}).get('output', '')
    match = re.search(r'Physical size:\s*(\d+)x(\d+)', device.get('display', ''))
    if match:
        values.update(AURORA_PANEL_WIDTH=match[1], AURORA_PANEL_HEIGHT=match[2])
    wireless = set(re.findall(r'^[A-Za-z0-9_.-]+$', output('wireless'), re.M))
    if len(wireless) == 1:
        values['AURORA_WIFI_IFACE'] = wireless.pop()
    backlights = re.findall(r'^(/sys/class/backlight/[A-Za-z0-9_.-]+)\|([0-9]+)$', output('backlights'), re.M)
    if len(backlights) == 1:
        values['AURORA_BACKLIGHT_PATH'] = backlights[0][0] + '/brightness'
    for key, pattern in (('AURORA_DRM_CARD', r'/dev/dri/card[0-9]+'), ('AURORA_DRM_RENDER_NODE', r'/dev/dri/renderD[0-9]+')):
        nodes = set(re.findall('^' + pattern + '$', output('drm'), re.M))
        if len(nodes) == 1:
            values[key] = nodes.pop()
    return values
