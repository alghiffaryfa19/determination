#!/bin/sh
set -eu
export PATH=/opt/hyprland/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CC=clang-19 CXX=clang++-19
export CMAKE_PREFIX_PATH=/opt/hyprland
export PKG_CONFIG_PATH=/opt/hyprland/lib/pkgconfig
export LD_LIBRARY_PATH=/opt/hyprland/lib
SRC=${1:-/root/build/hyprland/hyprland-qtutils}
if [ "${2:-build}" = deps ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends qt6-base-dev qt6-declarative-dev qt6-wayland-dev \
        qt6-base-private-dev qt6-declarative-private-dev qt6-wayland-private-dev \
        qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-templates \
        qml6-module-qtquick-window qml6-module-qtqml-workerscript qml6-module-qt-labs-platform
    exit
fi
cmake -S "$SRC" -B "$SRC/build-aurora" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/hyprland -DCMAKE_INSTALL_LIBDIR=lib
cmake --build "$SRC/build-aurora" -j "${AURORA_BUILD_JOBS:-4}"
cmake --install "$SRC/build-aurora"
