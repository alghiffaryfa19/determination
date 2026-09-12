#!/bin/sh
# Build libglibutil + libgbinder from pinned upstream sources. Debian obtains
# libgbinder from Droidian, but Arch and Alpine do not have to borrow a Debian
# package or enable a foreign repository.

set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TMPDIR=/tmp
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$HERE/sources.lock"
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH:-}
B=${B:-/root/build}
mkdir -p "$B"

if command -v aurora-platform >/dev/null 2>&1; then
    aurora-platform package-refresh
    aurora-platform deps libgbinder
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y git build-essential pkg-config libglib2.0-dev
fi

clone_pin() {
    repo=$1 commit=$2 destination=$3
    if [ ! -d "$destination/.git" ]; then
        git clone "$repo" "$destination"
    fi
    git -C "$destination" fetch --depth 1 origin "$commit"
    git -C "$destination" checkout --detach "$commit"
    [ "$(git -C "$destination" rev-parse HEAD)" = "$commit" ] || {
        echo "FATAL: source pin mismatch: $destination" >&2; exit 1;
    }
}

clone_pin "$LIBGLIBUTIL_REPO" "$LIBGLIBUTIL_COMMIT" "$B/libglibutil"
make -C "$B/libglibutil" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" release pkgconfig
make -C "$B/libglibutil" install-dev

clone_pin "$LIBGBINDER_REPO" "$LIBGBINDER_COMMIT" "$B/libgbinder"
make -C "$B/libgbinder" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" release pkgconfig
make -C "$B/libgbinder" install-dev
command -v ldconfig >/dev/null 2>&1 && ldconfig || true
pkg-config --exists libgbinder
echo "libgbinder built from pinned source"
