#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD=${AURORA_OPAL_BUILD_DIR:-"$HERE/build/opal-quickshell-cross"}
IMAGE=${AURORA_OPAL_BUILD_IMAGE:-aurora/quickshell-cross:trixie}

command -v podman >/dev/null 2>&1 || {
    echo 'podman is required for the host cross-build' >&2
    exit 1
}

mkdir -p "$BUILD"
command -v patch >/dev/null 2>&1 || { echo 'patch is required' >&2; exit 1; }
rm -rf "$BUILD/src"
cp -a "$HERE/guest/vendor/quickshell" "$BUILD/src"
if ! patch --dry-run -R -s -d "$BUILD/src" -p1 < "$HERE/guest/quickshell-vendor-egl.patch"; then
    patch -d "$BUILD/src" -p1 < "$HERE/guest/quickshell-vendor-egl.patch"
fi

if ! podman image exists "$IMAGE"; then
    podman build -t "$IMAGE" -f "$HERE/guest/Containerfile.quickshell-cross" "$HERE"
fi

exec podman run --rm \
    -v "$HERE:/work" \
    -v "$BUILD:/work/build/opal-quickshell-cross" \
    -w /work \
    "$IMAGE" /bin/bash -euc '
        set -o pipefail
        build=/work/build/opal-quickshell-cross
        qt=/usr/lib/aarch64-linux-gnu
        compgen -G "$qt/qt6/plugins/platforms/libqwayland*.so" >/dev/null || {
            echo "Qt Wayland runtime missing: rebuild guest/Containerfile.quickshell-cross" >&2
            exit 1
        }
        rm -rf "$build/build" "$build/install"
        mkdir -p "$build"
        sed -i "s|^pkg_get_variable(WAYLAND_PROTOCOLS wayland-protocols pkgdatadir)$|if(NOT WAYLAND_PROTOCOLS)\\n\\tpkg_get_variable(WAYLAND_PROTOCOLS wayland-protocols pkgdatadir)\\nendif()|" "$build/src/src/wayland/CMakeLists.txt"

        export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
        export PKG_CONFIG_SYSROOT_DIR=/
        cmake -S "$build/src" -B "$build/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SYSTEM_NAME=Linux \
            -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
            -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
            -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
            -DCMAKE_FIND_ROOT_PATH=/ \
            -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
            -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
            -DQt6_DIR=/usr/lib/aarch64-linux-gnu/cmake/Qt6 \
            -DQT_HOST_PATH=/usr \
            -DCMAKE_INSTALL_PREFIX=/opt/hyprland \
            -DDISTRIBUTOR=Aurora \
            -DCRASH_HANDLER=OFF -DUSE_JEMALLOC=OFF -DX11=OFF \
            -DSERVICE_PAM=OFF -DSERVICE_POLKIT=OFF -DSERVICE_PIPEWIRE=OFF \
            -DWAYLAND_PROTOCOLS=/work/guest/vendor/wayland-protocols \
            2>&1 | tee "$build/configure.log"
        cmake --build "$build/build" -j"$(nproc)" 2>&1 | tee "$build/build.log"
        DESTDIR="$build/install" cmake --install "$build/build" 2>&1 | tee "$build/install.log"
        # Qt private APIs require the same libraries and plugins used for this build.
        runtime="$build/install/opt/hyprland"
        mkdir -p "$runtime/lib/qt6"
        cp -a "$qt"/libQt6*.so* "$runtime/lib/"
        cp -a "$qt"/lib{icu,md4c,double-conversion,b2,ts}*.so* "$runtime/lib/"
        cp -a "$qt/qt6/plugins" "$qt/qt6/qml" "$runtime/lib/qt6/"
        printf "%s\n" "[Paths]" "Prefix=.." "Plugins=lib/qt6/plugins" \
            "QmlImports=lib/qt6/qml" > "$runtime/bin/qt.conf"
        dpkg-query -W -f="\${binary:Package}\t\${Version}\n" > "$build/runtime-packages.tsv"
    '
