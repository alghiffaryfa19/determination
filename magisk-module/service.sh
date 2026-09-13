#!/system/bin/sh
# Late-boot guest preparation; internal desktop mode remains user-triggered.

DET=/data/determination
mkdir -p "$DET/log" "$DET/run" "$DET/state"
[ "$(stat -c %s "$DET/log/service.log" 2>/dev/null || echo 0)" -gt 262144 ] &&
    tail -c 131072 "$DET/log/service.log" > "$DET/log/service.log.tmp" &&
    mv "$DET/log/service.log.tmp" "$DET/log/service.log"
exec >>"$DET/log/service.log" 2>&1
echo "--- service $(date)"

# Bound the boot wait so a degraded framework retains phone recovery.
i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    i=$((i + 1))
    if [ "$i" -ge 90 ]; then
        echo "WARN: boot completion deadline exceeded; leaving phone recovery intact"
        echo "boot_wait=deadline" > "$DET/run/boot-disposition"
        exit 0
    fi
    sleep 2
done
echo "boot_wait=complete" > "$DET/run/boot-disposition"

mkdir -p /sys/fs/cgroup/determination 2>/dev/null

# LXC requires Determination's PID namespaces and binderfs.
grep -q pid /proc/self/ns/pid 2>/dev/null || [ -e /proc/self/ns/pid ] || echo "WARN: no pid ns --- wrong kernel?"
[ -d /dev/binderfs ] || echo "WARN: binderfs missing --- wrong kernel?"

echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding || echo "WARN: no v6 forwarding (pre-#3 kernel?)"

# detd stays observe-only until native transition recovery is hardware-qualified.
if [ -x "$DET/bin/detd" ]; then
    [ "$(stat -c %s "$DET/log/detd.log" 2>/dev/null || echo 0)" -gt 262144 ] &&
        tail -c 131072 "$DET/log/detd.log" > "$DET/log/detd.log.tmp" &&
        mv "$DET/log/detd.log.tmp" "$DET/log/detd.log"
    if [ -S "$DET/run/detd.sock" ] && "$DET/bin/detctl" ping >/dev/null 2>&1; then
        echo "detd already running"
    else
        rm -f "$DET/run/detd.sock" "$DET/run/detd.pid"
        setsid "$DET/bin/detd" --root "$DET" --observe-only \
            >>"$DET/log/detd.log" 2>&1 &
        echo $! > "$DET/run/detd.pid"
        i=0
        while [ ! -S "$DET/run/detd.sock" ] && [ $i -lt 20 ]; do
            i=$((i+1)); sleep 0.1
        done
        if "$DET/bin/detctl" ping >/dev/null 2>&1; then
            echo "detd observe-only control plane ready"
        else
            echo "WARN: detd failed its boot ping (legacy controls unaffected)"
        fi
    fi
fi

# Force client composition only while the broken hardware Night Light path is active.
if [ -x "$DET/bin/det-color-compat" ]; then
    if [ -f "$DET/run/color-compat.pid" ]; then
        oldpid=$(cat "$DET/run/color-compat.pid" 2>/dev/null)
        [ -n "$oldpid" ] && kill "$oldpid" 2>/dev/null
    fi
    setsid "$DET/bin/det-color-compat" \
        >>"$DET/log/color-compat.log" 2>&1 &
    echo $! > "$DET/run/color-compat.pid"
fi

if [ -x "$DET/bin/guest-start" ]; then
    "$DET/bin/guest-start" || echo "WARN: guest-start failed"
fi

# Linux-first remains opt-in, profile-gated, and owned by the control daemon.
if [ -x "$DET/bin/boot-profile" ] && [ "$(sed -n 's/^desired=//p' "$DET/state/boot-profile" 2>/dev/null | tail -n 1)" = linux-first ]; then
    . "$DET/bin/device-config" || exit 0
    if [ "${DET_LINUX_FIRST_SUPPORTED:-0}" != 1 ]; then
        echo "linux-first requested but unsupported by this typed device profile" > "$DET/run/boot-disposition"
        "$DET/bin/boot-profile" phone >/dev/null 2>&1 || true
    elif "$DET/bin/boot-profile" apply >/dev/null 2>&1; then
        echo "linux-first=committed" > "$DET/run/boot-disposition"
    else
        "$DET/bin/boot-profile" failed >/dev/null 2>&1 || true
        echo "linux-first=recovered-phone-after-apply-failure" > "$DET/run/boot-disposition"
    fi
fi
