#!/bin/sh
# Install Droidian's architecture-independent Android 30 platform headers on a
# non-Debian guest. The exact .deb is only a signed-repository transport; no
# maintainer scripts or Debian package database are used.

set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$HERE/sources.lock"

pkg-config --exists 'android-headers >= 9.0.0' 2>/dev/null && exit 0
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v ar >/dev/null 2>&1 || { echo "ar is required" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
DEB="$WORK/android-headers-30.deb"
curl -fL "$ANDROID_HEADERS_30_URL" -o "$DEB"
printf '%s  %s\n' "$ANDROID_HEADERS_30_SHA256" "$DEB" | sha256sum -c -
(cd "$WORK" && ar x "$DEB")
DATA=$(find "$WORK" -maxdepth 1 -type f -name 'data.tar.*' | head -n 1)
[ -n "$DATA" ] || { echo "android headers archive has no data payload" >&2; exit 1; }
tar -xf "$DATA" -C /
pkg-config --exists 'android-headers >= 9.0.0' || {
    echo "android-headers pkg-config metadata missing after extraction" >&2
    exit 1
}
echo "installed pinned android-headers-30 payload"
