#!/bin/sh
# Cross-build the hyprgrass touch-gesture plugin for the pinned Hyprland port.
# The plugin ABI is version-locked: HYPRGRASS_COMMIT is the revision the plugin
# author's hyprpm table pairs with Hyprland v0.49.0 (9958d297). Install the
# result as /opt/hyprland/lib/libhyprgrass.so in the guest; the Omarchy session
# config loads it for every touch gesture binding.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$REPO/guest/sources.lock"

BUILD=${AURORA_HYPRGRASS_BUILD_DIR:-"$REPO/build/hyprgrass"}
SYSROOT=${AURORA_ARCH_SYSROOT:-"$REPO/build/arch-desktop/sysroot"}
PORT=${AURORA_HYPRLAND_PREFIX:-"$REPO/build/dethyprland-sysroot/opt/dethyprland"}
IMAGE=${AURORA_HYPRGRASS_IMAGE:-localhost/aurora/arch-desktop-cross:trixie}
JOBS=${AURORA_BUILD_JOBS:-4}
PORT_MOUNT=/sysroot/opt/dethyprland

command -v podman >/dev/null 2>&1 || { echo 'podman is required' >&2; exit 1; }
[ -d "$SYSROOT/usr/lib/pkgconfig" ] || { echo "missing Arch aarch64 sysroot: $SYSROOT" >&2; exit 1; }
[ -d "$PORT/include/hyprland" ] || { echo "missing Hyprland port prefix: $PORT" >&2; exit 1; }
[ -d "$SYSROOT/usr/include/glm" ] || {
    echo "sysroot lacks glm headers; keep glm in guest/prepare-arch-sysroot.sh" >&2; exit 1; }

if ! podman image exists "$IMAGE"; then
    podman build -t "$IMAGE" -f "$REPO/guest/Containerfile.arch-desktop" "$REPO"
fi

mkdir -p "$BUILD" "$PORT/lib/pkgconfig"
if [ ! -d "$BUILD/src/.git" ]; then
    git init "$BUILD/src"
    git -C "$BUILD/src" remote add origin "$HYPRGRASS_REPO"
    git -C "$BUILD/src" fetch --depth 1 origin "$HYPRGRASS_COMMIT"
    git -C "$BUILD/src" checkout --detach FETCH_HEAD
fi
[ "$(git -C "$BUILD/src" rev-parse HEAD)" = "$HYPRGRASS_COMMIT" ] || {
    echo 'hyprgrass source is not the pinned revision' >&2; exit 1; }

# The port installs Hyprland headers without a pkg-config file; provide the one
# meson asks for. PKG_CONFIG_SYSROOT_DIR rewrites these paths into the sysroot.
cat > "$PORT/lib/pkgconfig/hyprland.pc" <<'EOF'
prefix=/opt/dethyprland/include

Name: Hyprland
Description: Hyprland header files
Version: 0.49.0
Cflags: -I${prefix} -I${prefix}/hyprland/protocols -I${prefix}/hyprland
EOF

cat > "$BUILD/src/cross.ini" <<'EOF'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'
wayland-scanner = '/usr/bin/wayland-scanner'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'

[properties]
sys_root = '/sysroot'
needs_exe_wrapper = true

[built-in options]
c_args = ['--sysroot=/sysroot']
cpp_args = ['--sysroot=/sysroot', '-O2']
c_link_args = ['--sysroot=/sysroot', '-L/sysroot/usr/lib', '-Wl,-rpath-link,/sysroot/usr/lib']
cpp_link_args = ['--sysroot=/sysroot', '-L/sysroot/usr/lib', '-Wl,-rpath-link,/sysroot/usr/lib']
EOF

podman run --rm \
    -v "$SYSROOT:/sysroot:ro" \
    -v "$PORT:$PORT_MOUNT:ro" \
    -v "$BUILD/src:/work:rw" \
    -e PKG_CONFIG_LIBDIR="/sysroot/usr/lib/pkgconfig:/sysroot/usr/share/pkgconfig:$PORT_MOUNT/lib/pkgconfig" \
    -e PKG_CONFIG_SYSROOT_DIR=/sysroot \
    -w /work "$IMAGE" /bin/bash -euc "
        rm -rf build-cross
        meson setup build-cross --cross-file /work/cross.ini
        meson compile -C build-cross -j $JOBS
    "

cp -f "$BUILD/src/build-cross/src/libhyprgrass.so" "$BUILD/libhyprgrass.so"
echo "Wrote $BUILD/libhyprgrass.so"
