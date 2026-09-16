#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
export AURORA="$WORK/host" AURORA_GUEST_ROOT="$WORK/guest" AURORA_LOCK_HELD=1
mkdir -p "$AURORA/bin" "$AURORA_GUEST_ROOT/etc/libinput"
cat > "$AURORA/bin/device-config" <<'EOF'
AURORA_PANEL_WIDTH=1080
AURORA_PANEL_HEIGHT=2340
AURORA_HWC_OUTPUT=HWC-1
AURORA_OUTPUT_SCALE=2.5
AURORA_BATTERY_GAUGE=bms
AURORA_INPUT_QUIRK=${TEST_QUIRK:-none}
AURORA_GRAPHICS_RENDERER=libhybris
AURORA_GBM_PROVIDER=minigbm
AURORA_EXTERNAL_RENDERER=auto
AURORA_DRM_RENDER_NODE=/dev/dri/renderD128
AURORA_PANEL_REFRESH_MHZ=60000
EOF
: > "$AURORA/bin/lifecycle-lib"
printf '%s\n' 'user-owned override' > "$AURORA_GUEST_ROOT/etc/libinput/local-overrides.quirks"
QUIRKS="$AURORA_GUEST_ROOT/usr/share/libinput/99-aurora.quirks"
TEST_QUIRK=oneplus-touchpanel-zero-axes sh "$REPO/toggle/generate-guest-config"
grep -qx 'MatchName=touchpanel' "$QUIRKS"
grep -qx 'AttrEventCode=-ABS_MT_WIDTH_MAJOR;-ABS_MT_PRESSURE' "$QUIRKS"
grep -qx 'AttrInputProp=+INPUT_PROP_DIRECT;-INPUT_PROP_POINTER' "$QUIRKS"
[ "$(stat -c %a "$QUIRKS")" = 644 ]
cp "$QUIRKS" "$WORK/expected"
TEST_QUIRK=oneplus-touchpanel-zero-axes sh "$REPO/toggle/generate-guest-config"
cmp "$WORK/expected" "$QUIRKS"
TEST_QUIRK=none sh "$REPO/toggle/generate-guest-config"
[ ! -e "$QUIRKS" ]
grep -qx 'user-owned override' "$AURORA_GUEST_ROOT/etc/libinput/local-overrides.quirks"
if TEST_QUIRK=unknown sh "$REPO/toggle/generate-guest-config"; then
    echo 'unknown quirk accepted' >&2
    exit 1
fi
echo 'Guest input configuration tests passed'
