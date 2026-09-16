#!/bin/sh
# Native in-guest quickshell build for hyprland (Arch; the Debian shell is
# host-cross-built by build-opal-quickshell-cross.sh). Installs into
# /opt/hyprland alongside Hyprland. Run INSIDE the container.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${1:-/root/build/quickshell}
ACTION=${2:-build}
PREFIX=/opt/hyprland
JOBS=${AURORA_BUILD_JOBS:-2}

case "$ACTION" in
    deps)
        if command -v aurora-platform >/dev/null 2>&1; then
            aurora-platform package-refresh
            aurora-platform deps quickshell
        else
            echo 'aurora-platform is required for quickshell deps' >&2; exit 1
        fi
        exit
        ;;
    build) ;;
    *) echo 'usage: build-quickshell.sh [src] [deps|build]' >&2; exit 2 ;;
esac

[ -d "$SRC/.git" ] || {
    . "$HERE/sources.lock"
    git clone "$QUICKSHELL_REPO" "$SRC"
    git -C "$SRC" checkout --detach "$QUICKSHELL_COMMIT"
}
[ "$(git -C "$SRC" rev-parse HEAD)" = "$(. "$HERE/sources.lock"; printf '%s' "$QUICKSHELL_COMMIT")" ] || {
    echo 'quickshell source is not the pinned revision' >&2; exit 1;
}
if ! patch --dry-run -R -s -d "$SRC" -p1 < "$HERE/quickshell-vendor-egl.patch" 2>/dev/null; then
    patch --forward -d "$SRC" -p1 < "$HERE/quickshell-vendor-egl.patch" </dev/null
fi

export CMAKE_PREFIX_PATH=$PREFIX
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib

cmake -S "$SRC" -B "$SRC/build-aurora" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DDISTRIBUTOR=Aurora \
    -DCRASH_HANDLER=OFF -DUSE_JEMALLOC=OFF -DX11=OFF \
    -DSERVICE_PAM=OFF -DSERVICE_POLKIT=OFF -DSERVICE_PIPEWIRE=OFF
cmake --build "$SRC/build-aurora" -j"$JOBS"
cmake --install "$SRC/build-aurora"
"$PREFIX/bin/quickshell" --version
echo 'Quickshell installed into /opt/hyprland.'
