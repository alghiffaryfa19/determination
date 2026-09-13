#!/system/bin/sh
# Early blocking hook; guest startup belongs in the late-boot service.

MODDIR=${0%/*}
LOG=/data/determination/log
mkdir -p /data/determination
mkdir -p "$LOG"
exec >>"$LOG/post-fs-data.log" 2>&1
echo "--- post-fs-data $(date)"

# Every boot starts in phone mode; discard prior-boot runtime state.
if [ -f /data/determination/run/desktop-mode ]; then
    echo "stale desktop-mode state from previous boot --- clearing (boot = phone mode)"
fi
rm -rf /data/determination/run
mkdir -p /data/determination/run

# Recover an interrupted Linux-first transition before display ownership starts.
if [ -r /data/determination/state/boot-profile ]; then
    result=$(sed -n 's/^result=//p' /data/determination/state/boot-profile | tail -n 1)
    desired=$(sed -n 's/^desired=//p' /data/determination/state/boot-profile | tail -n 1)
    if [ "$desired" = linux-first ] && [ "$result" = entering ]; then
        sed 's/^desired=.*/desired=phone/; s/^result=.*/result=recovered-before-boot/' \
            /data/determination/state/boot-profile > /data/determination/state/boot-profile.new &&
            mv -f /data/determination/state/boot-profile.new /data/determination/state/boot-profile
        echo "incomplete Linux-first attempt recovered to phone"
    fi
fi

# Do not set unqualified framework props here; failures can block the lockscreen.
