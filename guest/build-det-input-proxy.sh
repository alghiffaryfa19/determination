#!/bin/sh
set -eu

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=${1:-/root/det-input-proxy.c}
PROTOCOL=${2:-/usr/share/plasma-wayland-protocols/fake-input.xml}
HEADERS=${3:-/root/determination-graphics}
OUT=${4:-/usr/local/bin/det-input-proxy}
BUILD=${TMPDIR:-/tmp}/det-input-proxy-build
WLR_POINTER=${5:-$HEADERS/protocols/wlr-virtual-pointer-unstable-v1.xml}
VIRTUAL_KEYBOARD=${6:-$HEADERS/protocols/virtual-keyboard-unstable-v1.xml}

rm -rf "$BUILD"
mkdir -p "$BUILD"
wayland-scanner client-header "$PROTOCOL" \
    "$BUILD/fake-input-client-protocol.h"
wayland-scanner private-code "$PROTOCOL" \
    "$BUILD/fake-input-protocol.c"
wayland-scanner client-header "$WLR_POINTER" \
    "$BUILD/wlr-virtual-pointer-client-protocol.h"
wayland-scanner private-code "$WLR_POINTER" \
    "$BUILD/wlr-virtual-pointer-protocol.c"
wayland-scanner client-header "$VIRTUAL_KEYBOARD" \
    "$BUILD/virtual-keyboard-client-protocol.h"
wayland-scanner private-code "$VIRTUAL_KEYBOARD" \
    "$BUILD/virtual-keyboard-protocol.c"

cc -std=c11 -O2 -Wall -Wextra -Werror \
    -I"$BUILD" -I"$HEADERS" \
    "$SRC" "$BUILD/fake-input-protocol.c" \
    "$BUILD/wlr-virtual-pointer-protocol.c" \
    "$BUILD/virtual-keyboard-protocol.c" -o "$OUT" \
    $(pkg-config --cflags --libs wayland-client)
