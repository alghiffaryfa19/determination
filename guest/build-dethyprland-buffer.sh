#!/bin/sh
# Display-safe vendor buffer gate; does not install or enable a session.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=${1:-/root/dethyprland}
OUT=${2:-/tmp/dethyprland-buffer-smoke}
[ -f /usr/local/lib/libEGL.so.1 ] || { echo 'libhybris is required' >&2; exit 2; }
c++ -std=c++20 -O2 -Wall -Wextra -Werror \
    -I/usr/local/include "$SRC/HybrisBuffer.cpp" "$SRC/buffer-smoke.cpp" \
    -L/usr/local/lib -Wl,-rpath,/usr/local/lib -lEGL -lGLESv2 -o "$OUT"
export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/aarch64-linux-gnu
export HYBRIS_LD_LIBRARY_PATH=/usr/lib/android:/vendor/lib64:/system/lib64:/odm/lib64:/apex/com.android.runtime/lib64/bionic
export ANDROID_ROOT=/system
exec "$OUT"
