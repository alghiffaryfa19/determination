#!/bin/sh
# Install signed ARM64 packages on the PC without executing target binaries.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
[ "$(id -u)" -eq 0 ] || { echo 'Run through aurora-installer build-guest.' >&2; exit 1; }
WORK="${AURORA_BUILD_ROOT:-$REPO/build}/arch-desktop"
ROOT="$WORK/sysroot"
mkdir -p "$WORK/cache" "$WORK/gnupg" "$WORK/hooks" "$ROOT"
chmod 700 "$WORK/gnupg"
if [ ! -f "$ROOT/etc/os-release" ]; then
    tar -xzf "${AURORA_ARCH_BASE:-$REPO/guest/aurora-rootfs-arch.tar.gz}" -C "$ROOT"
fi
gpg --homedir "$WORK/gnupg" --batch --no-autostart --import \
    "$ROOT/usr/share/pacman/keyrings/archlinuxarm.gpg"
for hook in "$ROOT"/usr/share/libalpm/hooks/*.hook; do
    [ -f "$hook" ] || continue
    ln -sf /dev/null "$WORK/hooks/${hook##*/}"
done
cat > "$WORK/pacman.conf" <<EOF
[options]
Architecture = aarch64
SigLevel = Required TrustAll DatabaseOptional
CacheDir = $WORK/cache
GPGDir = $WORK/gnupg
HookDir = $WORK/hooks
ParallelDownloads = 5
IgnorePkg = systemd systemd-libs systemd-sysvcompat systemd-resolvconf
[core]
Server = https://de3.mirror.archlinuxarm.org/aarch64/core
[extra]
Server = https://de3.mirror.archlinuxarm.org/aarch64/extra
[alarm]
Server = https://de3.mirror.archlinuxarm.org/aarch64/alarm
EOF
set -- \
    wayland wayland-protocols libdrm libglvnd libinput libxkbcommon pixman seatd \
    libevdev glib2 gobject-introspection-runtime gnome-desktop \
    gsettings-desktop-schemas json-glib xorg-xwayland libxcb libdisplay-info \
    libliftoff foot ttf-dejavu dbus phosh squeekboard gtk3 gtk4 libadwaita \
    libgmobile pipewire wireplumber sudo polkit xcb-util-wm libxml2 libxslt \
    libffi libpng libjpeg-turbo openssh dbus-broker pam acl libcap libseccomp openssl python
app_packages=$(python3 "$REPO/guest/aurora-apps" packages --root "$ROOT")
# Package names come from the shared, fixed profile, never from shell input.
set -- "$@" $app_packages
pacman --config "$WORK/pacman.conf" --root "$ROOT" \
    --dbpath "$ROOT/var/lib/pacman" --noscriptlet --noconfirm -Syuw --needed "$@"
python3 - "$WORK" <<'PY'
from pathlib import Path
import subprocess
import sys
work = Path(sys.argv[1])
for archive in (work / 'cache').glob('*.pkg.tar.*'):
    if archive.name.endswith('.sig'):
        continue
    for name in subprocess.check_output(['tar', '-tf', archive], text=True).splitlines():
        if name.startswith('usr/share/libalpm/hooks/') and name.endswith('.hook'):
            link = work / 'hooks' / Path(name).name
            if not link.is_symlink():
                link.symlink_to('/dev/null')
PY
pacman --config "$WORK/pacman.conf" --root "$ROOT" \
    --dbpath "$ROOT/var/lib/pacman" --noscriptlet --noconfirm -Su --needed "$@"
python3 "$REPO/guest/aurora-apps" check --root "$ROOT"
