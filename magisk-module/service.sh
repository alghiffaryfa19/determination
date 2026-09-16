#!/system/bin/sh
# Late-boot guest preparation; internal desktop mode remains user-triggered.

AURORA=/data/aurora
mkdir -p "$AURORA/log" "$AURORA/run" "$AURORA/state"
[ "$(stat -c %s "$AURORA/log/service.log" 2>/dev/null || echo 0)" -gt 262144 ] &&
    tail -c 131072 "$AURORA/log/service.log" > "$AURORA/log/service.log.tmp" &&
    mv "$AURORA/log/service.log.tmp" "$AURORA/log/service.log"
exec >>"$AURORA/log/service.log" 2>&1
echo "--- service $(date)"

# Bound the boot wait so a degraded framework retains phone recovery.
i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    i=$((i + 1))
    if [ "$i" -ge 90 ]; then
        echo "WARN: boot completion deadline exceeded; leaving phone recovery intact"
        echo "boot_wait=deadline" > "$AURORA/run/boot-disposition"
        exit 0
    fi
    sleep 2
done
echo "boot_wait=complete" > "$AURORA/run/boot-disposition"

mkdir -p /sys/fs/cgroup/aurora 2>/dev/null

# LXC requires Aurora's PID namespaces and binderfs.
grep -q pid /proc/self/ns/pid 2>/dev/null || [ -e /proc/self/ns/pid ] || echo "WARN: no pid ns --- wrong kernel?"
[ -d /dev/binderfs ] || echo "WARN: binderfs missing --- wrong kernel?"

echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding || echo "WARN: no v6 forwarding (pre-#3 kernel?)"

# aurorad stays observe-only until native transition recovery is hardware-qualified.
if [ -x "$AURORA/bin/aurorad" ]; then
    [ "$(stat -c %s "$AURORA/log/aurorad.log" 2>/dev/null || echo 0)" -gt 262144 ] &&
        tail -c 131072 "$AURORA/log/aurorad.log" > "$AURORA/log/aurorad.log.tmp" &&
        mv "$AURORA/log/aurorad.log.tmp" "$AURORA/log/aurorad.log"
    if [ -S "$AURORA/run/aurorad.sock" ] && "$AURORA/bin/auroractl" ping >/dev/null 2>&1; then
        echo "aurorad already running"
    else
        rm -f "$AURORA/run/aurorad.sock" "$AURORA/run/aurorad.pid"
        setsid "$AURORA/bin/aurorad" --root "$AURORA" --observe-only \
            >>"$AURORA/log/aurorad.log" 2>&1 &
        echo $! > "$AURORA/run/aurorad.pid"
        i=0
        while [ ! -S "$AURORA/run/aurorad.sock" ] && [ $i -lt 20 ]; do
            i=$((i+1)); sleep 0.1
        done
        if "$AURORA/bin/auroractl" ping >/dev/null 2>&1; then
            echo "aurorad observe-only control plane ready"
        else
            echo "WARN: aurorad failed its boot ping (legacy controls unaffected)"
        fi
    fi
fi

# Force client composition only while the broken hardware Night Light path is active.
if [ -x "$AURORA/bin/aurora-color-compat" ]; then
    if [ -f "$AURORA/run/color-compat.pid" ]; then
        oldpid=$(cat "$AURORA/run/color-compat.pid" 2>/dev/null)
        [ -n "$oldpid" ] && kill "$oldpid" 2>/dev/null
    fi
    setsid "$AURORA/bin/aurora-color-compat" \
        >>"$AURORA/log/color-compat.log" 2>&1 &
    echo $! > "$AURORA/run/color-compat.pid"
fi

if [ -x "$AURORA/bin/guest-start" ]; then
    "$AURORA/bin/guest-start" || echo "WARN: guest-start failed"
fi

# Linux-first remains opt-in, profile-gated, and owned by the control daemon.
if [ -x "$AURORA/bin/boot-profile" ] && [ "$(sed -n 's/^desired=//p' "$AURORA/state/boot-profile" 2>/dev/null | tail -n 1)" = linux-first ]; then
    . "$AURORA/bin/device-config" || exit 0
    if [ "${AURORA_LINUX_FIRST_SUPPORTED:-0}" != 1 ]; then
        echo "linux-first requested but unsupported by this typed device profile" > "$AURORA/run/boot-disposition"
        "$AURORA/bin/boot-profile" phone >/dev/null 2>&1 || true
    elif "$AURORA/bin/boot-profile" apply >/dev/null 2>&1; then
        echo "linux-first=committed" > "$AURORA/run/boot-disposition"
    else
        "$AURORA/bin/boot-profile" failed >/dev/null 2>&1 || true
        echo "linux-first=recovered-phone-after-apply-failure" > "$AURORA/run/boot-disposition"
    fi
fi
