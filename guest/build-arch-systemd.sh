#!/bin/sh
# Cross-build Arch's kernel-4.14-compatible init without executing target code.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$REPO"
BUILD=${AURORA_BUILD_ROOT:-$REPO/build}
WORK=$BUILD/arch-systemd
if [ "${1:-}" != --inside ]; then
    mkdir -p "$WORK"
    ARCHIVE="$WORK/systemd-v257.13.tar.gz"
    if [ ! -f "$ARCHIVE" ]; then
        mkdir -p "$(dirname "$ARCHIVE")"
        curl -fL https://github.com/systemd/systemd/archive/refs/tags/v257.13.tar.gz -o "$ARCHIVE.partial"
        mv "$ARCHIVE.partial" "$ARCHIVE"
    fi
    printf '%s  %s\n' 1eb7d5f9ff8a426ff880a3cded9ce819613ba8003ac5ddde9eca162f14ddabe7 "$ARCHIVE" | sha256sum -c -
    if [ ! -f "$WORK/source/meson.build" ]; then
        mkdir -p "$WORK/source"
        tar -xzf "$ARCHIVE" --strip-components=1 -C "$WORK/source"
    fi
    [ -f "$BUILD/arch-desktop/sysroot/usr/lib/libc.so.6" ] || {
        echo 'Arch sysroot missing: run guest/prepare-arch-sysroot.sh' >&2; exit 1;
    }
    IMAGE=${AURORA_ARCH_BUILD_IMAGE:-localhost/aurora/alarm-cross:trixie}
    if ! podman image exists "$IMAGE"; then
        podman build -t "$IMAGE" -f guest/Containerfile.alarm-cross .
    fi
    exec podman run --rm -v "$REPO:/work:ro" -v "$BUILD:/build" \
        -e AURORA_BUILD_ROOT=/build -w /work "$IMAGE" sh guest/build-arch-systemd.sh --inside
fi
python3 - "$REPO/guest/arch-systemd-cross.ini" "$WORK/cross.ini" "$BUILD" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text().replace('/work/build', sys.argv[3]))
PY
meson setup --clearcache --reconfigure "$WORK/build" "$WORK/source" \
    --cross-file "$WORK/cross.ini" --prefix=/usr --libdir=lib \
    "-Dc_link_args=['--sysroot=$BUILD/arch-desktop/sysroot', '-L$BUILD/arch-desktop/sysroot/usr/lib', '-Wl,-rpath-link,$BUILD/arch-desktop/sysroot/usr/lib']" \
    --buildtype=release -Dmode=release -Dversion-tag=257.13-aurora \
    -Dtests=false -Dinstall-tests=false -Dman=disabled -Dhtml=disabled -Dtranslations=false \
    -Dbootloader=disabled -Dukify=disabled -Dkernel-install=false -Defi=false -Dtpm=false \
    -Drepart=disabled -Dsysupdate=disabled -Dsysupdated=disabled -Dhomed=disabled \
    -Dnetworkd=false -Dresolve=false -Dtimesyncd=false -Dfirstboot=false \
    -Dselinux=disabled -Dapparmor=disabled -Daudit=disabled -Dpwquality=disabled \
    -Dqrencode=disabled -Dlibfido2=disabled -Dtpm2=disabled -Dlibcryptsetup=disabled \
    -Dp11kit=disabled -Dgnutls=disabled -Dgcrypt=disabled -Dopenssl=enabled \
    -Dlibidn=disabled -Dlibidn2=disabled -Dseccomp=enabled -Dpam=enabled -Dacl=enabled \
    -Dlogind=true -Doomd=false -Dportabled=false -Dmachined=false -Duserdb=false \
    -Dhibernate=false -Dmountfsd=false -Dsysext=false -Dinitrd=false -Dsysvinit-path= -Dsysvrcnd-path= \
    -Dimportd=false -Dremote=false \
    -Ddbuspolicydir=/usr/share/dbus-1/system.d \
    -Ddbussessionservicedir=/usr/share/dbus-1/services \
    -Ddbussystemservicedir=/usr/share/dbus-1/system-services \
    -Ddbus-interfaces-dir=/usr/share/dbus-1/interfaces
ninja -C "$WORK/build" -j "${AURORA_BUILD_JOBS:-6}"
DESTDIR="$WORK/install" meson install -C "$WORK/build" --no-rebuild
# Newer libudev cannot enumerate evdev on 4.14; isolate the qualified ABI from pacman.
install -D -m 0644 "$WORK/install/usr/lib/libudev.so.1" \
    "$WORK/install/opt/hyprland/lib/compat/libudev.so.1"
sha256sum "$WORK/install/opt/hyprland/lib/compat/libudev.so.1" \
    > "$WORK/libudev-compat.sha256"
