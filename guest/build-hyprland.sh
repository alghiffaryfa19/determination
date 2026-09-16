#!/bin/sh
# Build the isolated port baseline; never activate its upstream DRM backend.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=${1:-/root/build/hyprland}
PREFIX=/opt/hyprland
JOBS=${AURORA_BUILD_JOBS:-2}
if command -v clang-19 >/dev/null 2>&1; then
    export CC=clang-19 CXX=clang++-19
    SCAN_DEPS=/usr/bin/clang-scan-deps-19
else
    export CC=clang CXX=clang++
    SCAN_DEPS=/usr/bin/clang-scan-deps
fi
export CMAKE_PREFIX_PATH=$PREFIX
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib
case "${2:-build}" in
    deps)
        if command -v aurora-platform >/dev/null 2>&1 && [ "$(aurora-platform id)" != debian ]; then
            aurora-platform package-refresh
            aurora-platform deps hyprland
            exit
        fi
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends clang-19 clang-tools-19 cmake meson ninja-build \
            pkg-config git libpugixml-dev libpixman-1-dev libwayland-dev wayland-protocols \
            libseat-dev libinput-dev libdrm-dev libgbm-dev libudev-dev libdisplay-info-dev \
            hwdata libegl-dev libgles-dev libcairo2-dev libpango1.0-dev libjpeg-dev \
            libwebp-dev libmagic-dev libspng-dev libzip-dev librsvg2-dev libtomlplusplus-dev \
            libxkbcommon-dev uuid-dev libxcursor-dev libre2-dev libsystemd-dev \
            libxcb-composite0-dev libxcb-ewmh-dev libxcb-icccm4-dev libxcb-render-util0-dev \
            libxcb-res0-dev libxcb-xinput-dev libxcb-errors-dev xwayland squeekboard
        exit
        ;;
    build) ;;
    *) echo 'usage: build-hyprland.sh <sources> [deps|build]' >&2; exit 2 ;;
esac
[ -d "$SRC/Hyprland/.git" ] || { echo 'run fetch-hyprland.sh first' >&2; exit 2; }
for project in hyprwayland-scanner hyprutils hyprlang hyprcursor hyprgraphics aquamarine; do
    cmake -S "$SRC/$project" -B "$SRC/$project/build-aurora" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_TESTING=OFF
    cmake --build "$SRC/$project/build-aurora" -j "$JOBS"
    cmake --install "$SRC/$project/build-aurora"
done
if [ ! -d "$SRC/hyprland-protocols/build-aurora/meson-private" ]; then
    meson setup "$SRC/hyprland-protocols/build-aurora" "$SRC/hyprland-protocols" --prefix="$PREFIX"
fi
meson install -C "$SRC/hyprland-protocols/build-aurora"
cmake -S "$SRC/Hyprland" -B "$SRC/Hyprland/build-aurora" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib -DNO_HYPRPM=ON -DNO_UWSM=ON \
    -DCMAKE_CXX_COMPILER_CLANG_SCAN_DEPS="$SCAN_DEPS"
cmake --build "$SRC/Hyprland/build-aurora" -j "$JOBS"
cmake --install "$SRC/Hyprland/build-aurora"
echo 'Built isolated Hyprland baseline. HWC integration is required before panel launch.'
