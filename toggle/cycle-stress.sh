#!/system/bin/sh
# Cycle-stress the §4 toggle: a single clean toggle proves nothing; repeated
# cycling is where the HAL state machine and fd-ownership bugs surface.
# Watches for wedge (SF not returning) and GPU-context/fd leaks.
# Usage: cycle-stress.sh [iterations]   (default 50)

set -u
AURORA=/data/aurora
N="${1:-50}"
case "$N" in ''|*[!0-9]*) echo "iterations must be a positive integer" >&2; exit 2;; esac
mkdir -p "$AURORA/metrics"
OUT="$AURORA/metrics/cycle-$(date +%Y%m%d-%H%M%S).log"
exec >"$OUT" 2>&1

fd_count() { ls "/proc/$(pidof "$1" | cut -d' ' -f1)/fd" 2>/dev/null | wc -l; }
composer_pid() { pidof vendor.qti.hardware.display.composer-service \
    || pidof android.hardware.graphics.composer@2.4-service \
    || pidof android.hardware.graphics.composer@2.3-service; }

CP=$(composer_pid | awk '{print $1}')
BASE_FD=$(fd_count "$CP" 2>/dev/null || true)
echo "qualification schema=1 commit=$(cat "$AURORA/current/manifest-id" 2>/dev/null || echo unknown) profile=$(sha256sum "$AURORA/etc/device.conf" 2>/dev/null | awk '{print $1}' || echo none)"
echo "composer HAL pid=${CP:-unknown} baseline_fds=${BASE_FD:-unknown}"

wait_state() { # wanted timeout ticks
    wanted=$1; limit=$2; n=0
    while [ "$n" -lt "$limit" ]; do
        [ "$(sed -n 's/^state=//p' "$AURORA/run/transition.state" 2>/dev/null | tail -n 1)" = "$wanted" ] && return 0
        n=$((n + 1)); sleep 1
    done
    return 1
}

i=1
while [ "$i" -le "$N" ]; do
    echo "== cycle $i/$N"
    began=$(date +%s)
    "$AURORA/bin/desktop-on"  || { echo "FAIL: desktop-on cycle=$i"; exit 1; }
    wait_state DESKTOP 45 || { echo "FAIL: desktop state timeout cycle=$i"; "$AURORA/bin/desktop-off" --emergency || true; exit 1; }
    entered=$(( $(date +%s) - began ))
    "$AURORA/bin/desktop-off" || { echo "FAIL: desktop-off cycle=$i"; exit 1; }
    wait_state PHONE 45 || { echo "FAIL: phone state timeout cycle=$i"; exit 1; }
    [ "$(getprop init.svc.surfaceflinger)" = "running" ] || { echo "WEDGE: SF dead after cycle $i"; exit 1; }
    CP=$(composer_pid | awk '{print $1}'); FDS=$(ls "/proc/$CP/fd" 2>/dev/null | wc -l)
    KGSL=$(grep -c . /sys/class/kgsl/kgsl/proc/*/cmdline 2>/dev/null | wc -l)
    echo "cycle=$i entered_s=$entered composer_pid=${CP:-unknown} fds=$FDS fd_delta=$((FDS - ${BASE_FD:-FDS})) kgsl_procs=$KGSL"
    i=$((i+1))
done
echo "PASS: $N cycles evidence=$OUT"
