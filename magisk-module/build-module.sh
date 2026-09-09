#!/bin/sh
# Package the Determination Magisk module zip (install via Magisk app -> Modules
# -> Install from storage; no META-INF needed for app installs).
# Pulls the device evgrab binary and toggle scripts in as payload.

set -eu
cd "$(dirname "$0")"
REPO=$(cd .. && pwd)
. "$REPO/release/version.sh"
det_load_version "$REPO/version.properties"

[ -f ../tools/evgrab/evgrab ] || { echo "build evgrab for aarch64 first (tools/evgrab, make CC=aarch64-linux-gnu-gcc)" >&2; exit 1; }
file ../tools/evgrab/evgrab | grep -q aarch64 || { echo "evgrab is not an aarch64 build" >&2; exit 1; }
INPUT_FORWARDER="../tools/input-forwarder/det-input-forwarder"
[ -f "$INPUT_FORWARDER" ] || { echo "build det-input-forwarder with the Android NDK first" >&2; exit 1; }
file "$INPUT_FORWARDER" | grep -q 'ARM aarch64' || { echo "det-input-forwarder is not an Android aarch64 build" >&2; exit 1; }

DETD="../control/build/android-arm64/detd"
DETCTL="../control/build/android-arm64/detctl"
DET_GUEST_AGENT="../control/build/guest-arm64/det-guest-agent"
DET_AUDIO_HOST="../audio/build/android-arm64/det-audio-probe"
DET_AUDIO_GUEST="../audio/build/guest-arm64/det-audio-probe"
DET_AUDIO_OWNER="../audio/build/android-arm64/det-audio-owner"
for binary in "$DETD" "$DETCTL"; do
    [ -f "$binary" ] || {
        echo "build the native control plane first (./control/build.sh android)" >&2
        exit 1
    }
    file "$binary" | grep -q 'ARM aarch64' || {
        echo "$binary is not an Android aarch64 build" >&2
        exit 1
    }
done
[ -f "$DET_GUEST_AGENT" ] || {
    echo "build the Debian guest agent first (./control/build.sh guest)" >&2
    exit 1
}
file "$DET_GUEST_AGENT" | grep -q 'ARM aarch64' || {
    echo "$DET_GUEST_AGENT is not a Linux aarch64 build" >&2
    exit 1
}
file "$DET_GUEST_AGENT" | grep -q 'statically linked' || {
    echo "$DET_GUEST_AGENT must be rebuilt as a distro-neutral static guest binary" >&2
    exit 1
}
for binary in "$DET_AUDIO_HOST" "$DET_AUDIO_GUEST" "$DET_AUDIO_OWNER"; do
    [ -f "$binary" ] || {
        echo "build the direct audio probes first (./audio/build.sh all)" >&2
        exit 1
    }
    file "$binary" | grep -q 'ARM aarch64' || {
        echo "$binary is not an aarch64 build" >&2
        exit 1
    }
done
file "$DET_AUDIO_GUEST" | grep -q 'statically linked' || {
    echo "$DET_AUDIO_GUEST must be rebuilt as a distro-neutral static guest binary" >&2
    exit 1
}

ZYGISK_64="../zygisk/libs/arm64-v8a/libdetermination.so"
ZYGISK_32="../zygisk/libs/armeabi-v7a/libdetermination.so"
[ -f "$ZYGISK_64" ] || { echo "build the zygisk module first (cd zygisk && ndk-build)" >&2; exit 1; }
[ -f "$ZYGISK_32" ] || { echo "build the zygisk module first (cd zygisk && ndk-build)" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp customize.sh post-fs-data.sh service.sh sepolicy.rule "$WORK/"
det_render_version_template module.prop.in "$WORK/module.prop"
mkdir -p "$WORK/tools" "$WORK/guest-tools" "$WORK/guest-assets" "$WORK/zygisk" \
    "$WORK/device-profiles" "$WORK/audio-profiles"
cp ../tools/evgrab/evgrab "$INPUT_FORWARDER" \
   "$DETD" "$DETCTL" "$DET_AUDIO_HOST" "$DET_AUDIO_OWNER" \
   ../toggle/device-config ../toggle/generate-lxc-config ../toggle/generate-guest-config \
   ../toggle/lifecycle-lib ../toggle/boot-profile ../toggle/guest-distro \
   ../toggle/guest-start ../toggle/desktop-on ../toggle/desktop-off \
   ../toggle/desktop-memory \
    ../toggle/session-catalog ../toggle/session-select ../toggle/session-set \
   ../toggle/run-transition ../toggle/external-presenter ../toggle/external-input \
   ../toggle/native-plasma ../toggle/native-kms-gate ../toggle/native-restore \
   ../toggle/det-hostagent ../toggle/det-color-compat \
   ../toggle/cycle-stress.sh ../audio/det-audio-route ../audio/det-audio-smoke \
   "$WORK/tools/"
cp ../device-profiles/*.conf "$WORK/device-profiles/"
cp ../audio/profiles/*.conf "$WORK/audio-profiles/"
mkdir -p "$WORK/sessions" "$WORK/guest-config"
cp ../guest/sessions/*.session "$WORK/sessions/"
cp ../guest/hyprland.conf "$WORK/guest-config/hyprland.conf"
cp ../guest/hyprland-opal.conf "$WORK/guest-config/hyprland-opal.conf"
cp "$DET_GUEST_AGENT" "$WORK/guest-tools/det-guest-agent"
cp "$DET_AUDIO_GUEST" "$WORK/guest-tools/det-audio-probe"
cp ../guest/det-audio-session "$WORK/guest-tools/det-audio-session"
cp ../guest/det-pipewire-smoke "$WORK/guest-tools/det-pipewire-smoke"
cp ../guest/det-input-actions "$WORK/guest-tools/det-input-actions"
cp ../guest/det-media-action "$WORK/guest-tools/det-media-action"
cp ../guest/det-connectivity "$WORK/guest-tools/det-connectivity"
cp ../guest/det-connectivity-menu "$WORK/guest-tools/det-connectivity-menu"
cp ../guest/det-platform "$WORK/guest-tools/det-platform"
cp ../guest/det-phosh-session "$WORK/guest-tools/det-phosh-session"
cp ../guest/det-compat-check "$WORK/guest-tools/det-compat-check"
cp ../guest/det-firefox-content-defaults "$WORK/guest-tools/det-firefox-content-defaults"
cp ../guest/det-session-launch "$WORK/guest-tools/det-session-launch"
cp ../guest/det-plasma-session "$WORK/guest-tools/det-plasma-session"
cp ../guest/det-plasma-client "$WORK/guest-tools/det-plasma-client"
cp ../guest/det-hyprland "$WORK/guest-tools/det-hyprland"
cp ../guest/det-hyprland-opal "$WORK/guest-tools/det-hyprland-opal"
cp ../guest/det-opal "$WORK/guest-tools/det-opal"
cp ../guest/det-opal-bridge "$WORK/guest-tools/det-opal-bridge"
cp ../guest/opal-command "$WORK/guest-tools/opal"
cp -a ../guest/opal "$WORK/guest-assets/opal"
cp ../guest/setup-compatibility.sh "$WORK/guest-tools/setup-compatibility.sh"
cp ../guest/det-phosh.service "$WORK/guest-tools/det-phosh.service"
cp ../guest/det-plasma.service "$WORK/guest-tools/det-plasma.service"
cp ../guest/determination-connectivity.desktop "$WORK/guest-tools/determination-connectivity.desktop"
cp ../guest/determination-input-proxy.desktop "$WORK/guest-tools/determination-input-proxy.desktop"
cp ../guest/det-input-udevdb "$WORK/guest-tools/det-input-udevdb"
cp ../guest/90-determination-direct.conf "$WORK/guest-tools/90-determination-direct.conf"
cp ../guest/lxc/config "$WORK/tools/lxc-config-base"
cp "$ZYGISK_64" "$WORK/zygisk/arm64-v8a.so"
cp "$ZYGISK_32" "$WORK/zygisk/armeabi-v7a.so"

OUT="$PWD/determination-magisk-v$DET_VERSION.zip"
rm -f "$OUT"
# Python zipfile keeps this independent of zip(1). Fixed metadata plus a
# sorted file list make repeated release builds byte-for-byte reproducible.
(cd "$WORK" && SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}" python3 - "$OUT" <<'PY'
import os, stat, sys, time, zipfile
out = sys.argv[1]
epoch = max(315532800, int(os.environ['SOURCE_DATE_EPOCH']))
stamp = time.gmtime(epoch)[:6]
paths = sorted(os.path.relpath(os.path.join(root, name), '.')
               for root, dirs, files in os.walk('.') for name in files)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in paths:
        info = zipfile.ZipInfo(path, stamp)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (stat.S_IFREG | 0o644) << 16
        with open(path, 'rb') as src:
            z.writestr(info, src.read(), compress_type=zipfile.ZIP_DEFLATED,
                       compresslevel=9)
PY
)
echo "Wrote ${OUT##*/}"
python3 -c "import zipfile; print('\n'.join(zipfile.ZipFile('$OUT').namelist()))"
