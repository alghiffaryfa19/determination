#!/bin/sh
# Build KWin's virtual-EGL Android-gralloc output backend.
#
# KWin stays entirely in the Mesa/minigbm world. The separate
# det-gralloc-pool process owns libhybris, complete Android native handles and
# the Android presenter connection. Their only boundary is dma-buf metadata
# plus acquire/release sync_file fences.
set -eu

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LANG=C.UTF-8
export PKG_CONFIG_PATH=/opt/minigbm/lib/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig

SOURCE=${1:-/usr/src/kwin-6.3.6}
PATCH=${2:-/root/kwin-6.3.6-gralloc-pool.patch}
HEADER=${3:-/root/gralloc-pool-protocol.h}
BUILD=${4:-/var/tmp/determination-kwin-build}

[ -f "$SOURCE/src/backends/virtual/virtual_egl_backend.cpp" ] || {
    echo "FATAL: KWin 6.3.6 source missing at $SOURCE" >&2
    exit 2
}
[ -r "$PATCH" ] && [ -r "$HEADER" ] || {
    echo "FATAL: gralloc-pool KWin patch or protocol header missing" >&2
    exit 2
}

install -D -m 0644 "$HEADER" \
    /usr/local/include/determination/gralloc-pool-protocol.h

if ! grep -q DETERMINATION_GRALLOC_POOL \
        "$SOURCE/src/backends/virtual/virtual_egl_backend.cpp"; then
    patch -d "$SOURCE" -p1 < "$PATCH"
fi

cmake -S "$SOURCE" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -Dgbm_LIBRARY=/opt/minigbm/lib/libgbm.so \
    -Dgbm_INCLUDE_DIR=/opt/minigbm/include \
    -DBUILD_TESTING=OFF \
    -DKWIN_BUILD_KCMS=OFF \
    -DKWIN_BUILD_X11=OFF \
    -DKWIN_BUILD_X11_BACKEND=OFF \
    -DKWIN_BUILD_NOTIFICATIONS=OFF \
    -DKWIN_BUILD_SCREENLOCKER=OFF \
    -DKWIN_BUILD_RUNNERS=OFF \
    -DKWIN_BUILD_ACTIVITIES=OFF \
    -DKWIN_BUILD_EIS=OFF
cmake --build "$BUILD" --target kwin -- -j1

echo "Built KWin gralloc-pool backend in $BUILD (not installed)."
