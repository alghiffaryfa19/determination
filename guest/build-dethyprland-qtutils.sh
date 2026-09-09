#!/bin/sh
set -eu
export PATH=/opt/dethyprland/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CC=clang-19 CXX=clang++-19
export CMAKE_PREFIX_PATH=/opt/dethyprland
export PKG_CONFIG_PATH=/opt/dethyprland/lib/pkgconfig
export LD_LIBRARY_PATH=/opt/dethyprland/lib
SRC=${1:-/root/build/dethyprland/hyprland-qtutils}
if [ "${2:-build}" = deps ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends qt6-base-dev qt6-declarative-dev qt6-wayland-dev \
        qt6-base-private-dev qt6-declarative-private-dev qt6-wayland-private-dev \
        qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-templates \
        qml6-module-qtquick-window qml6-module-qtqml-workerscript qml6-module-qt-labs-platform
    exit
fi
cmake -S "$SRC" -B "$SRC/build-det" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/dethyprland -DCMAKE_INSTALL_LIBDIR=lib
cmake --build "$SRC/build-det" -j "${DET_BUILD_JOBS:-4}"
cmake --install "$SRC/build-det"
