#!/bin/sh
# Queue the ABI-changing patches after the currently running baseline build.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PID=${1:?baseline ninja pid required}
case "$PID" in *[!0-9]*|'') exit 2 ;; esac
while [ "$(cat "/proc/$PID/comm" 2>/dev/null || true)" = ninja ]; do sleep 5; done
export AURORA_BUILD_JOBS=${AURORA_BUILD_JOBS:-4}
sh /root/patch-aurorahyprland.sh
sh /root/build-aurorahyprland.sh /root/build/aurorahyprland
printf 'Renderer-patched build finished; HWC output and input integration are still required.\n'
