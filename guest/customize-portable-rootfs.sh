#!/bin/sh
# Add Aurora's distro-neutral contract to an extracted rootfs.
# This does not execute foreign-architecture binaries. Runtime packages and the
# uid/gid contract are completed by /root/aurora-firstboot in LXC.

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
    "$ROOT/root/aurora-build" "$ROOT/usr/local/bin" \
    "$ROOT/usr/local/sbin" "$ROOT/usr/lib/aurora"
# Rootfs archives are not consistent about preserving the standard sticky
# mode. Unprivileged sessions and build probes must be able to use /tmp.
install -d -m 1777 "$ROOT/tmp"
install -m 0755 "$HERE/aurora-platform" "$ROOT/usr/local/bin/aurora-platform"
install -m 0755 "$HERE/aurora-phosh-session" "$ROOT/usr/local/bin/aurora-phosh-session"
install -m 0755 "$HERE/aurora-compat-check" "$ROOT/usr/local/bin/aurora-compat-check"
install -m 0755 "$HERE/aurora-firefox-content-defaults" \
    "$ROOT/usr/local/bin/aurora-firefox-content-defaults"
install -m 0755 "$HERE/setup-compatibility.sh" "$ROOT/usr/local/sbin/setup-compatibility.sh"
install -D -m 0644 "$HERE/aurora-phosh.service" \
    "$ROOT/usr/local/lib/aurora/aurora-phosh.service"
install -m 0644 "$HERE/sources.lock" "$ROOT/root/aurora-build/sources.lock"
for build_file in install-android-headers.sh build-libgbinder.sh \
                  build-libhybris.sh patch-libhybris-musl.py \
                  build-wlroots-phoc.sh setup-input.sh; do
    install -m 0755 "$HERE/$build_file" "$ROOT/root/aurora-build/$build_file"
done

cat > "$ROOT/etc/aurora-profile" <<EOF
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
# ALARM's absolute resolved symlink points outside an offline rootfs.
rm -f "$ROOT/etc/resolv.conf"
cat > "$ROOT/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:3
EOF

if [ "$PROFILE" = arch ]; then
    install -d "$ROOT/etc/systemd/system" "$ROOT/etc/ssh/sshd_config.d"
    for service in systemd-networkd.service systemd-networkd.socket \
                   systemd-resolved.service systemd-timesyncd.service \
                   getty@tty1.service console-getty.service; do
        ln -sf /dev/null "$ROOT/etc/systemd/system/$service"
    done
    # 4.14 has no Landlock: pacman's filesystem sandbox can never work here.
    if [ -f "$ROOT/etc/pacman.conf" ]; then
        sed -i 's/^#DisableSandboxFilesystem/DisableSandboxFilesystem/' "$ROOT/etc/pacman.conf"
        # systemd 261+ needs statx mount IDs absent before 6.8: PID1 exits on 4.14.
        # Aurora ships a 257.13 replacement (build/omarchy-alarm); keep
        # pacman from upgrading the init system back over it. Belongs in
        # [options]: appending would land in a trailing repo section.
        grep -q '^IgnorePkg = .*systemd' "$ROOT/etc/pacman.conf" 2>/dev/null || \
            sed -i 's/^#IgnorePkg   =/#IgnorePkg   =\
IgnorePkg = systemd systemd-libs systemd-sysvcompat systemd-resolvconf/' \
                "$ROOT/etc/pacman.conf"
    fi
    cat > "$ROOT/etc/ssh/sshd_config.d/00-aurora.conf" <<'EOF_SSH'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
AllowUsers aurora
EOF_SSH
fi

cat > "$ROOT/root/aurora-firstboot" <<'EOF'
#!/bin/sh
# Run once as root after this rootfs has booted inside Aurora's LXC.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[ "$(id -u)" -eq 0 ] || { echo "FATAL: run as root" >&2; exit 1; }
[ -x /usr/local/bin/aurora-platform ] || { echo "FATAL: aurora-platform missing" >&2; exit 1; }
[ ! -e /etc/aurora-ready ] || { echo "Aurora guest already provisioned"; exit 0; }

echo "== refresh package metadata =="
if [ "$(aurora-platform id)" = arch ]; then
    pacman-key --init
    pacman-key --populate archlinuxarm
fi
aurora-platform package-refresh
echo "== base runtime =="
aurora-platform deps runtime
echo "== mobile session packages =="
aurora-platform deps phosh

ensure_group() {
    name=$1 gid=$2
    getent group "$name" >/dev/null 2>&1 && return 0
    case "$(aurora-platform id)" in
        alpine) addgroup -g "$gid" "$name" ;;
        *) groupadd -g "$gid" "$name" ;;
    esac
}

ensure_group android_graphics 1003
ensure_group android_input 1004
ensure_group android_audio 1005

uid1000_user=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -n "$uid1000_user" ] && [ "$uid1000_user" != aurora ]; then
    # Generic Arch Linux ARM images traditionally ship `alarm` as uid 1000.
    # The numeric uid is load-bearing for Android GPU/audio nodes, so rename the
    # account instead of creating a second user or changing its number.
    uid1000_group=$(id -gn "$uid1000_user")
    usermod -l aurora -d /home/aurora -m "$uid1000_user"
    if [ "$uid1000_group" != aurora ] && ! getent group aurora >/dev/null 2>&1; then
        groupmod -n aurora "$uid1000_group"
    fi
elif ! id aurora >/dev/null 2>&1; then
    case "$(aurora-platform id)" in
        alpine) adduser -D -u 1000 -s /bin/sh aurora ;;
        *) useradd -m -u 1000 -s /bin/bash aurora ;;
    esac
fi

for group in video input render audio seat android_graphics android_input android_audio; do
    getent group "$group" >/dev/null 2>&1 || continue
    case "$(aurora-platform id)" in
        alpine) addgroup aurora "$group" 2>/dev/null || true ;;
        *) usermod -aG "$group" aurora ;;
    esac
done

setup-compatibility.sh

install -d -m 0750 /etc/sudoers.d
printf '%s\n' 'aurora ALL=(ALL) ALL' > /etc/sudoers.d/aurora
chmod 0440 /etc/sudoers.d/aurora
printf '%s\n' aurora > /etc/hostname
grep -q aurora /etc/hosts 2>/dev/null || \
    printf '127.0.0.1\tlocalhost\n127.0.1.1\taurora\n' > /etc/hosts

case "$(aurora-platform init)" in
    systemd)
        systemctl mask getty@tty1.service console-getty.service >/dev/null 2>&1 || true
        # Fresh-boot desktop launch needs the bus, seat and login management
        # before runuser/PAM works: without these the compositor supervisor
        # hangs in epoll and the input seat attempt fails the backend.
        systemctl enable dbus-broker.service seatd.service >/dev/null 2>&1 || true
        ;;
    openrc)
        rc-update add dbus default >/dev/null 2>&1 || true
        rc-update add seatd default >/dev/null 2>&1 || true
        ;;
esac

cat > /etc/aurora-ready <<EOF_READY
profile=$(aurora-platform id)
libc=$(aurora-platform libc)
init=$(aurora-platform init)
contract=1
graphics=unqualified
EOF_READY
echo "Aurora guest base is ready. Build libhybris and the patched phoc stack before desktop qualification."
EOF
chmod 0755 "$ROOT/root/aurora-firstboot"

# BusyBox init in Alpine's minirootfs invokes OpenRC but also spawns six gettys.
# They are useless in this container and fight Aurora's synthetic VTs.
if [ "$PROFILE" = alpine ] && [ -f "$ROOT/etc/inittab" ]; then
    sed -i '/^tty[1-6]::respawn:/d' "$ROOT/etc/inittab"
fi

echo "customized $name rootfs at $ROOT"
