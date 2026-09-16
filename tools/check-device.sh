#!/bin/sh
# Non-destructive acceptance against a currently running Aurora desktop.
# It reads live process/device state and runs a fake terminal backend; it does
# not restart the compositor, open windows, toggle the OSK, or grab input.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ADB=${ADB:-adb}
REMOTE=/data/local/tmp/aurora-runtime-check.$$
GUEST=/data/aurora/active-guest/root/aurora-runtime-check.$$
GUEST_INNER=/root/aurora-runtime-check.$$

[ "$($ADB get-state 2>/dev/null)" = device ] || { echo 'no adb device' >&2; exit 1; }
$ADB push "$ROOT/guest/aurora-runtime-check" "$REMOTE" >/dev/null
cleanup() {
    $ADB shell "su -c 'rm -f $REMOTE $GUEST'" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

$ADB shell "su -c 'cp $REMOTE $GUEST && chmod 0755 $GUEST && \
    /data/aurora/lxc/bin/lxc-attach -P /data/aurora -n guest -- \
    /bin/sh $GUEST_INNER'"

echo 'live device acceptance passed'
