#!/system/bin/sh
# Early blocking hook; guest startup belongs in the late-boot service.

MODDIR=${0%/*}
LOG=/data/aurora/log
mkdir -p /data/aurora
mkdir -p "$LOG"
exec >>"$LOG/post-fs-data.log" 2>&1
echo "--- post-fs-data $(date)"

# Every boot starts in phone mode; discard prior-boot runtime state.
if [ -f /data/aurora/run/desktop-mode ]; then
    echo "stale desktop-mode state from previous boot --- clearing (boot = phone mode)"
fi
rm -rf /data/aurora/run
mkdir -p /data/aurora/run

# Recover an interrupted Linux-first transition before display ownership starts.
if [ -r /data/aurora/state/boot-profile ]; then
    result=$(sed -n 's/^result=//p' /data/aurora/state/boot-profile | tail -n 1)
    desired=$(sed -n 's/^desired=//p' /data/aurora/state/boot-profile | tail -n 1)
    if [ "$desired" = linux-first ] && [ "$result" = entering ]; then
        sed 's/^desired=.*/desired=phone/; s/^result=.*/result=recovered-before-boot/' \
            /data/aurora/state/boot-profile > /data/aurora/state/boot-profile.new &&
            mv -f /data/aurora/state/boot-profile.new /data/aurora/state/boot-profile
        echo "incomplete Linux-first attempt recovered to phone"
    fi
fi

# Do not set unqualified framework props here; failures can block the lockscreen.
