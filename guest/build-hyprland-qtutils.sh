#!/bin/sh
# Cross-build hyprland-qtutils for the guest. Hyprland calls hyprland-dialog
# for ANR dialogs, dynamic-permission prompts, and confirmations; without it
# those features disable themselves and log an error at startup.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$REPO/guest/sources.lock"

BUILD=${AURORA_QTUTILS_BUILD_DIR:-"$REPO/build/hyprland-qtutils"}
PORT=${AURORA_HYPRLAND_PREFIX:-"$REPO/build/dethyprland-sysroot/opt/dethyprland"}
IMAGE=${AURORA_QTUTILS_IMAGE:-aurora/quickshell-cross:trixie}
JOBS=${AURORA_BUILD_JOBS:-4}

command -v podman >/dev/null 2>&1 || { echo 'podman is required' >&2; exit 1; }
[ -d "$PORT/include/hyprland" ] || { echo "missing Hyprland port prefix: $PORT" >&2; exit 1; }
if ! podman image exists "$IMAGE"; then
    podman build -t "$IMAGE" -f "$REPO/guest/Containerfile.quickshell-cross" "$REPO"
fi

mkdir -p "$BUILD"
if [ ! -d "$BUILD/src/.git" ]; then
    git init "$BUILD/src"
    git -C "$BUILD/src" remote add origin "$HYPRLAND_QTUTILS_REPO"
    git -C "$BUILD/src" fetch --depth 1 origin "$HYPRLAND_QTUTILS_COMMIT"
    git -C "$BUILD/src" checkout --detach FETCH_HEAD
fi
[ "$(git -C "$BUILD/src" rev-parse HEAD)" = "$HYPRLAND_QTUTILS_COMMIT" ] || {
    echo 'hyprland-qtutils source is not the pinned revision' >&2; exit 1; }

rm -rf "$BUILD/src/build-cross"
# hyprutils in the port prefix carries unresolved pixman references until the
# guest resolves them at runtime, so the link must tolerate shlib undefineds.
podman run --rm \
    -v "$BUILD/src:/work:rw" \
    -v "$PORT:/opt/dethyprland:ro" \
    "$IMAGE" /bin/bash -euc "
        export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig:/opt/dethyprland/lib/pkgconfig
        cmake -S /work -B /work/build-cross -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
            -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
            -DCMAKE_FIND_ROOT_PATH=/ -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
            -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
            -DQt6_DIR=/usr/lib/aarch64-linux-gnu/cmake/Qt6 -DQT_HOST_PATH=/usr \
            -DCMAKE_INSTALL_PREFIX=/opt/hyprland \
            -DCMAKE_EXE_LINKER_FLAGS='-Wl,--unresolved-symbols=ignore-in-shared-libs -Wl,-rpath-link,/opt/dethyprland/lib'
        cmake --build /work/build-cross -j $JOBS
    "

mkdir -p "$BUILD/install"
for tool in dialog/hyprland-dialog update-screen/hyprland-update-screen donate-screen/hyprland-donate-screen; do
    cp -f "$BUILD/src/build-cross/utils/$tool" "$BUILD/install/$(basename "$tool")"
done
echo "Wrote qtutils binaries into $BUILD/install"
