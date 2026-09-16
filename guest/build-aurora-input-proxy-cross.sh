#!/bin/sh
# Cross-build aurora-input-proxy for the guest. The proxy turns the host's
# USB/Bluetooth evdev stream (delivered over the control FIFO) into wlroots
# virtual-pointer and virtual-keyboard events, so external peripherals work
# while the guest owns the session.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD=${AURORA_INPUT_PROXY_BUILD_DIR:-"$REPO/build/aurora-input-proxy"}
SYSROOT=${AURORA_ARCH_SYSROOT:-"$REPO/build/arch-desktop/sysroot"}
IMAGE=${AURORA_INPUT_PROXY_IMAGE:-aurora/arch-desktop-cross:trixie}

command -v podman >/dev/null 2>&1 || { echo 'podman is required' >&2; exit 1; }
[ -d "$SYSROOT/usr/lib/pkgconfig" ] || { echo "missing Arch aarch64 sysroot: $SYSROOT" >&2; exit 1; }
if ! podman image exists "$IMAGE"; then
    podman build -t "$IMAGE" -f "$REPO/guest/Containerfile.arch-desktop" "$REPO"
fi

mkdir -p "$BUILD"
podman run --rm \
    -v "$REPO:/work:ro" \
    -v "$BUILD:/out:rw" \
    -v "$SYSROOT:/sysroot:ro" \
    -e CC="aarch64-linux-gnu-gcc --sysroot=/sysroot" \
    -e PKG_CONFIG_LIBDIR=/sysroot/usr/lib/pkgconfig:/sysroot/usr/share/pkgconfig \
    -e PKG_CONFIG_SYSROOT_DIR=/sysroot \
    "$IMAGE" \
    sh /work/guest/build-aurora-input-proxy.sh \
        /work/guest/aurora-input-proxy.c \
        /work/graphics/protocols/fake-input.xml \
        /work/graphics \
        /out/aurora-input-proxy \
        /work/graphics/protocols/wlr-virtual-pointer-unstable-v1.xml \
        /work/graphics/protocols/virtual-keyboard-unstable-v1.xml

file "$BUILD/aurora-input-proxy" | grep -q 'ARM aarch64' || {
    echo 'aurora-input-proxy is not an aarch64 build' >&2; exit 1; }
echo "Wrote $BUILD/aurora-input-proxy"
