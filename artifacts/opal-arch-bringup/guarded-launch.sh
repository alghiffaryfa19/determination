#!/system/bin/sh
set -eu
A=/data/aurora
[ ! -e "$A/run/desktop-mode" ] || exit 2
setsid /system/bin/sh -c 'sleep 120; /data/aurora/bin/desktop-off > /data/aurora/log/opal-timed-restore.log 2>&1' </dev/null >/dev/null 2>&1 &
echo "restore_guard=$!"
"$A/bin/desktop-on"
