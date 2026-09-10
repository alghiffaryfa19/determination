#!/bin/sh
# Add Determination's distro-neutral contract to an extracted rootfs.
# This does not execute foreign-architecture binaries. Runtime packages and the
# uid/gid contract are completed by /root/determination-firstboot in LXC.

set -eu
[ "$#" -eq 2 ] || { echo "usage: $0 ROOTFS arch|alpine" >&2; exit 2; }
ROOT=$1
PROFILE=$2
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

case "$PROFILE" in
    arch)
        name='Arch Linux ARM'
        libc=glibc
        init=systemd
        ;;
    alpine)
        name='Alpine Linux'
        libc=musl
        init=openrc
        ;;
    *) echo "unsupported profile: $PROFILE" >&2; exit 2 ;;
esac

[ -e "$ROOT/bin/busybox" ] || [ -e "$ROOT/usr/bin/sh" ] || [ -e "$ROOT/bin/bash" ] || {
    echo "rootfs has no usable shell payload: $ROOT" >&2
    exit 1
}
install -d "$ROOT/etc" "$ROOT/etc/profile.d" "$ROOT/root" \
    "$ROOT/root/determination-build" "$ROOT/usr/local/bin" \
    "$ROOT/usr/local/sbin" "$ROOT/usr/lib/determination"
# Rootfs archives are not consistent about preserving the standard sticky
# mode. Unprivileged sessions and build probes must be able to use /tmp.
install -d -m 1777 "$ROOT/tmp"
install -m 0755 "$HERE/det-platform" "$ROOT/usr/local/bin/det-platform"
install -m 0755 "$HERE/det-phosh-session" "$ROOT/usr/local/bin/det-phosh-session"
install -m 0755 "$HERE/det-compat-check" "$ROOT/usr/local/bin/det-compat-check"
install -m 0755 "$HERE/det-firefox-content-defaults" \
    "$ROOT/usr/local/bin/det-firefox-content-defaults"
install -m 0755 "$HERE/setup-compatibility.sh" "$ROOT/usr/local/sbin/setup-compatibility.sh"
install -D -m 0644 "$HERE/det-phosh.service" \
    "$ROOT/usr/local/lib/determination/det-phosh.service"
install -m 0644 "$HERE/sources.lock" "$ROOT/root/determination-build/sources.lock"
for build_file in install-android-headers.sh build-libgbinder.sh \
                  build-libhybris.sh patch-libhybris-musl.py \
                  build-wlroots-phoc.sh setup-input.sh; do
    install -m 0755 "$HERE/$build_file" "$ROOT/root/determination-build/$build_file"
done

cat > "$ROOT/etc/determination-profile" <<EOF
ID=$PROFILE
NAME=$name
LIBC=$libc
INIT=$init
ARCH=aarch64
STATUS=device-unverified
CONTRACT=1
EOF

cat > "$ROOT/etc/profile.d/hybris.sh" <<'EOF'
export EGL_PLATFORM=wayland
export HYBRIS_EGLPLATFORM=wayland
export ANDROID_ROOT=/system
export HYBRIS_LD_LIBRARY_PATH=/usr/lib/android:/vendor/lib64:/system/lib64:/odm/lib64:/apex/com.android.runtime/lib64/bionic
EOF

ln -snf /system/product "$ROOT/product"
ln -snf /system/system_ext "$ROOT/system_ext"
cat > "$ROOT/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:3
EOF

cat > "$ROOT/root/determination-firstboot" <<'EOF'
#!/bin/sh
# Run once as root after this rootfs has booted inside Determination's LXC.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[ "$(id -u)" -eq 0 ] || { echo "FATAL: run as root" >&2; exit 1; }
[ -x /usr/local/bin/det-platform ] || { echo "FATAL: det-platform missing" >&2; exit 1; }
[ ! -e /etc/determination-ready ] || { echo "Determination guest already provisioned"; exit 0; }

echo "== refresh package metadata =="
det-platform package-refresh
echo "== base runtime =="
det-platform deps runtime
echo "== mobile session packages =="
det-platform deps phosh

ensure_group() {
    name=$1 gid=$2
    getent group "$name" >/dev/null 2>&1 && return 0
    case "$(det-platform id)" in
        alpine) addgroup -g "$gid" "$name" ;;
        *) groupadd -g "$gid" "$name" ;;
    esac
}

ensure_group android_graphics 1003
ensure_group android_input 1004
ensure_group android_audio 1005

uid1000_user=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -n "$uid1000_user" ] && [ "$uid1000_user" != detuser ]; then
    # Generic Arch Linux ARM images traditionally ship `alarm` as uid 1000.
    # The numeric uid is load-bearing for Android GPU/audio nodes, so rename the
    # account instead of creating a second user or changing its number.
    uid1000_group=$(id -gn "$uid1000_user")
    usermod -l detuser -d /home/detuser -m "$uid1000_user"
    if [ "$uid1000_group" != detuser ] && ! getent group detuser >/dev/null 2>&1; then
        groupmod -n detuser "$uid1000_group"
    fi
elif ! id detuser >/dev/null 2>&1; then
    case "$(det-platform id)" in
        alpine) adduser -D -u 1000 -s /bin/sh detuser ;;
        *) useradd -m -u 1000 -s /bin/bash detuser ;;
    esac
fi

for group in video input render audio android_graphics android_input android_audio; do
    getent group "$group" >/dev/null 2>&1 || continue
    case "$(det-platform id)" in
        alpine) addgroup detuser "$group" 2>/dev/null || true ;;
        *) usermod -aG "$group" detuser ;;
    esac
done

setup-compatibility.sh

install -d -m 0750 /etc/sudoers.d
printf '%s\n' 'detuser ALL=(ALL) ALL' > /etc/sudoers.d/detuser
chmod 0440 /etc/sudoers.d/detuser
printf '%s\n' determination > /etc/hostname
grep -q determination /etc/hosts 2>/dev/null || \
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tdetermination\n' > /etc/hosts

case "$(det-platform init)" in
    systemd)
        systemctl mask getty@tty1.service console-getty.service >/dev/null 2>&1 || true
        ;;
    openrc)
        rc-update add dbus default >/dev/null 2>&1 || true
        rc-update add seatd default >/dev/null 2>&1 || true
        ;;
esac

cat > /etc/determination-ready <<EOF_READY
profile=$(det-platform id)
libc=$(det-platform libc)
init=$(det-platform init)
contract=1
graphics=unqualified
EOF_READY
echo "Determination guest base is ready. Build libhybris and the patched phoc stack before desktop qualification."
EOF
chmod 0755 "$ROOT/root/determination-firstboot"

# BusyBox init in Alpine's minirootfs invokes OpenRC but also spawns six gettys.
# They are useless in this container and fight Determination's synthetic VTs.
if [ "$PROFILE" = alpine ] && [ -f "$ROOT/etc/inittab" ]; then
    sed -i '/^tty[1-6]::respawn:/d' "$ROOT/etc/inittab"
fi

echo "customized $name rootfs at $ROOT"
