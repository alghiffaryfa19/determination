#!/bin/sh
# Package the Aurora Magisk module zip (install via Magisk app -> Modules
# -> Install from storage; no META-INF needed for app installs).
# Pulls the device evgrab binary and toggle scripts in as payload.

set -eu
cd "$(dirname "$0")"
REPO=$(cd .. && pwd)
. "$REPO/release/version.sh"
aurora_load_version "$REPO/version.properties"

[ -f ../tools/evgrab/evgrab ] || { echo "build evgrab for aarch64 first (tools/evgrab, make CC=aarch64-linux-gnu-gcc)" >&2; exit 1; }
file ../tools/evgrab/evgrab | grep -q aarch64 || { echo "evgrab is not an aarch64 build" >&2; exit 1; }
INPUT_FORWARDER="../tools/input-forwarder/aurora-input-forwarder"
[ -f "$INPUT_FORWARDER" ] || { echo "build aurora-input-forwarder with the Android NDK first" >&2; exit 1; }
file "$INPUT_FORWARDER" | grep -q 'ARM aarch64' || { echo "aurora-input-forwarder is not an Android aarch64 build" >&2; exit 1; }

AURORAD="../control/build/android-arm64/aurorad"
AURORACTL="../control/build/android-arm64/auroractl"
AURORA_GUEST_AGENT="../control/build/guest-arm64/aurora-guest-agent"
AURORA_AUDIO_HOST="../audio/build/android-arm64/aurora-audio-probe"
AURORA_AUDIO_GUEST="../audio/build/guest-arm64/aurora-audio-probe"
AURORA_AUDIO_OWNER="../audio/build/android-arm64/aurora-audio-owner"
for binary in "$AURORAD" "$AURORACTL"; do
    [ -f "$binary" ] || {
        echo "build the native control plane first (./control/build.sh android)" >&2
        exit 1
    }
    file "$binary" | grep -q 'ARM aarch64' || {
        echo "$binary is not an Android aarch64 build" >&2
        exit 1
    }
done
[ -f "$AURORA_GUEST_AGENT" ] || {
    echo "build the Debian guest agent first (./control/build.sh guest)" >&2
    exit 1
}
file "$AURORA_GUEST_AGENT" | grep -q 'ARM aarch64' || {
    echo "$AURORA_GUEST_AGENT is not a Linux aarch64 build" >&2
    exit 1
}
file "$AURORA_GUEST_AGENT" | grep -q 'statically linked' || {
    echo "$AURORA_GUEST_AGENT must be rebuilt as a distro-neutral static guest binary" >&2
    exit 1
}
for binary in "$AURORA_AUDIO_HOST" "$AURORA_AUDIO_GUEST" "$AURORA_AUDIO_OWNER"; do
    [ -f "$binary" ] || {
        echo "build the direct audio probes first (./audio/build.sh all)" >&2
        exit 1
    }
    file "$binary" | grep -q 'ARM aarch64' || {
        echo "$binary is not an aarch64 build" >&2
        exit 1
    }
done
file "$AURORA_AUDIO_GUEST" | grep -q 'statically linked' || {
    echo "$AURORA_AUDIO_GUEST must be rebuilt as a distro-neutral static guest binary" >&2
    exit 1
}

ZYGISK_64="../zygisk/libs/arm64-v8a/libaurora.so"
ZYGISK_32="../zygisk/libs/armeabi-v7a/libaurora.so"
[ -f "$ZYGISK_64" ] || { echo "build the zygisk module first (cd zygisk && ndk-build)" >&2; exit 1; }
[ -f "$ZYGISK_32" ] || { echo "build the zygisk module first (cd zygisk && ndk-build)" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp customize.sh post-fs-data.sh service.sh sepolicy.rule "$WORK/"
aurora_render_version_template module.prop.in "$WORK/module.prop"
mkdir -p "$WORK/tools" "$WORK/guest-tools" "$WORK/guest-assets" "$WORK/zygisk" \
    "$WORK/device-profiles" "$WORK/audio-profiles"
cp ../tools/evgrab/evgrab "$INPUT_FORWARDER" \
   "$AURORAD" "$AURORACTL" "$AURORA_AUDIO_HOST" "$AURORA_AUDIO_OWNER" \
   ../toggle/device-config ../toggle/generate-lxc-config ../toggle/generate-guest-config \
   ../toggle/lifecycle-lib ../toggle/boot-profile ../toggle/guest-distro \
   ../toggle/guest-start ../toggle/desktop-on ../toggle/desktop-off \
   ../toggle/desktop-memory \
    ../toggle/session-catalog ../toggle/session-select ../toggle/session-set \
   ../toggle/run-transition ../toggle/external-presenter ../toggle/external-input \
   ../toggle/native-plasma ../toggle/native-kms-gate ../toggle/native-restore \
   ../toggle/aurora-hostagent ../toggle/aurora-color-compat \
   ../toggle/cycle-stress.sh ../audio/aurora-audio-route ../audio/aurora-audio-smoke \
   "$WORK/tools/"
cp ../device-profiles/*.conf "$WORK/device-profiles/"
cp ../audio/profiles/*.conf "$WORK/audio-profiles/"
mkdir -p "$WORK/sessions" "$WORK/guest-config"
cp ../guest/sessions/*.session "$WORK/sessions/"
cp ../guest/hyprland.conf "$WORK/guest-config/hyprland.conf"
cp ../guest/hyprland-opal.conf "$WORK/guest-config/hyprland-opal.conf"
cp ../guest/hyprland-omarchy.conf "$WORK/guest-config/hyprland-omarchy.conf"
cp "$AURORA_GUEST_AGENT" "$WORK/guest-tools/aurora-guest-agent"
cp "$AURORA_AUDIO_GUEST" "$WORK/guest-tools/aurora-audio-probe"
cp ../guest/aurora-audio-session "$WORK/guest-tools/aurora-audio-session"
cp ../guest/aurora-pipewire-smoke "$WORK/guest-tools/aurora-pipewire-smoke"
cp ../guest/aurora-input-actions "$WORK/guest-tools/aurora-input-actions"
cp ../guest/aurora-media-action "$WORK/guest-tools/aurora-media-action"
cp ../guest/aurora-connectivity "$WORK/guest-tools/aurora-connectivity"
cp ../guest/aurora-connectivity-menu "$WORK/guest-tools/aurora-connectivity-menu"
cp ../guest/aurora-platform "$WORK/guest-tools/aurora-platform"
cp ../guest/aurora-apps "$WORK/guest-tools/aurora-apps"
cp ../guest/aurora-phosh-session "$WORK/guest-tools/aurora-phosh-session"
cp ../guest/aurora-compat-check "$WORK/guest-tools/aurora-compat-check"
cp ../guest/aurora-osk "$WORK/guest-tools/aurora-osk"
cp ../guest/aurora-firefox-content-defaults "$WORK/guest-tools/aurora-firefox-content-defaults"
cp ../guest/aurora-session-launch "$WORK/guest-tools/aurora-session-launch"
cp ../guest/aurora-plasma-session "$WORK/guest-tools/aurora-plasma-session"
cp ../guest/aurora-plasma-client "$WORK/guest-tools/aurora-plasma-client"
cp ../guest/aurora-hyprland "$WORK/guest-tools/aurora-hyprland"
cp ../guest/aurora-hyprland-opal "$WORK/guest-tools/aurora-hyprland-opal"
cp ../guest/aurora-opal "$WORK/guest-tools/aurora-opal"
cp ../guest/aurora-omarchy "$WORK/guest-tools/aurora-omarchy"
cp ../guest/aurora-hyprland-omarchy "$WORK/guest-tools/aurora-hyprland-omarchy"
cp -a ../guest/omarchy "$WORK/guest-assets/omarchy"
cp ../guest/aurora-opal-bridge "$WORK/guest-tools/aurora-opal-bridge"
cp ../guest/opal-command "$WORK/guest-tools/opal"
cp -a ../guest/opal "$WORK/guest-assets/opal"
cp ../guest/setup-compatibility.sh "$WORK/guest-tools/setup-compatibility.sh"
cp ../guest/aurora-phosh.service "$WORK/guest-tools/aurora-phosh.service"
cp ../guest/aurora-plasma.service "$WORK/guest-tools/aurora-plasma.service"
cp ../guest/aurora-connectivity.desktop "$WORK/guest-tools/aurora-connectivity.desktop"
cp ../guest/aurora-input-proxy.desktop "$WORK/guest-tools/aurora-input-proxy.desktop"
cp ../guest/aurora-input-udevdb "$WORK/guest-tools/aurora-input-udevdb"
cp ../guest/90-aurora-direct.conf "$WORK/guest-tools/90-aurora-direct.conf"
cp ../guest/lxc/config "$WORK/tools/lxc-config-base"
cp "$ZYGISK_64" "$WORK/zygisk/arm64-v8a.so"
cp "$ZYGISK_32" "$WORK/zygisk/armeabi-v7a.so"

OUT="$PWD/aurora-magisk-v$AURORA_VERSION.zip"
rm -f "$OUT"
# Python zipfile keeps this independent of zip(1). Fixed timestamps plus a
# sorted file list make repeated release builds byte-for-byte reproducible;
# the Unix mode is preserved so guest-assets keep their executable bit.
(cd "$WORK" && SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}" python3 - "$OUT" <<'PY'
import os, sys, time, zipfile
out = sys.argv[1]
epoch = max(315532800, int(os.environ['SOURCE_DATE_EPOCH']))
stamp = time.gmtime(epoch)[:6]
paths = sorted(os.path.relpath(os.path.join(root, name), '.')
               for root, dirs, files in os.walk('.') for name in files)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in paths:
        info = zipfile.ZipInfo(path, stamp)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = os.stat(path).st_mode << 16
        with open(path, 'rb') as src:
            z.writestr(info, src.read(), compress_type=zipfile.ZIP_DEFLATED,
                       compresslevel=9)
PY
)
echo "Wrote ${OUT##*/}"
python3 -c "import zipfile; print('\n'.join(zipfile.ZipFile('$OUT').namelist()))"
