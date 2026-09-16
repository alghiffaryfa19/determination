#!/bin/sh
# Assemble the enriched sysroot, not the original base archive.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD=${AURORA_BUILD_ROOT:-$REPO/build}
ROOT=$BUILD/arch-desktop/sysroot
INIT=$BUILD/arch-systemd/install
OUT=$BUILD/aurora-rootfs-arch.tar.gz
for file in "$ROOT/usr/local/bin/phoc" "$ROOT/usr/local/lib/libEGL.so.1" \
            "$INIT/usr/lib/systemd/systemd" \
            "$INIT/opt/hyprland/lib/compat/libudev.so.1"; do
    [ -f "$file" ] || { echo "missing rootfs build output: $file" >&2; exit 1; }
done
WORK=$(mktemp -d "$BUILD/assemble.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir "$WORK/root"
cp -a "$ROOT/." "$WORK/root/"
cp -a "$INIT/." "$WORK/root/"
sh "$REPO/guest/customize-portable-rootfs.sh" "$WORK/root" arch
python3 "$REPO/guest/aurora-apps" check --root "$WORK/root"
rm -f "$WORK/root/etc/aurora-ready" "$WORK/root/var/lib/aurora/apps.json"
mkdir -p "$WORK/root/usr/share/aurora"
python3 "$REPO/guest/aurora-apps" packages --root "$WORK/root" \
    > "$WORK/root/usr/share/aurora/image-app-packages.txt"
printf '%s\n' 'graphics=phoc-build-only' 'hyprland-opal=separate-runtime-required' \
    'applications=installed-not-graphically-qualified' 'postinstall=aurora-firstboot-required' \
    > "$WORK/root/usr/share/aurora/image-qualification"
tar --numeric-owner -C "$WORK/root" -czf "$WORK/rootfs.tar.gz" .
mv -f "$WORK/rootfs.tar.gz" "$OUT"
echo "Enriched Arch rootfs: $OUT"
