#!/bin/sh
set -eu

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=${1:-/root/aurora-gralloc-pool.c}
CLIENT=${2:-/root/presenter-client.c}
HEADERS=${3:-/root/aurora-graphics}
OUT=${4:-/usr/local/bin/aurora-gralloc-pool}

cc -std=c11 -O2 -Wall -Wextra -Werror \
    -I/usr/local/include -I/opt/minigbm/include -I"$HEADERS" \
    $(pkg-config --cflags libdrm) \
    "$SRC" "$CLIENT" -o "$OUT" \
    -L/usr/local/lib -L/opt/minigbm/lib \
    -Wl,-rpath,/usr/local/lib -Wl,-rpath,/opt/minigbm/lib \
    -lEGL -lhybris-common -lgbm $(pkg-config --libs libdrm)
