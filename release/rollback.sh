#!/bin/sh
# Roll the active guest rootfs slot back to a previously installed distro.
#
# Plan-only by default: prints the exact ordered commands an operator (or
# `det shell`) would run. --execute performs them over adb, gated behind an
# interactive confirmation and a hard refusal when no phone is attached.
#
# Slot layout per docs/design-spec.md:
#   /data/determination/active-guest          -> current slot id
#   /data/determination/guests/<id>/rootfs    -> installed slots
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)"

usage() { echo "usage: rollback.sh [--execute] <slot-id>" >&2; exit 2; }

execute=false
case "${1:-}" in
    --execute) execute=true; shift ;;
esac
slot=${1:-}; [ -n "$slot" ] || usage
case $slot in *[!A-Za-z0-9_.-]*) echo "invalid slot id: $slot" >&2; exit 2 ;; esac

command -v adb >/dev/null 2>&1 || { echo "adb not found" >&2; exit 1; }
if ! adb get-state >/dev/null 2>&1; then
    addr=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $NF; exit}')
    [ -n "$addr" ] && adb connect "$addr" >/dev/null
    adb get-state >/dev/null 2>&1 || { echo "no phone attached" >&2; exit 1; }
fi
serial=$(adb devices | awk 'NR==2{print $1}')

G=/data/determination
remote_check=$(adb shell "su -c 'id=\$(cat $G/active-guest 2>/dev/null); \\
    echo \"current=\$id\"; \\
    [ -d \"$G/guests/$slot/rootfs\" ] && echo \"slot=ok\" || echo \"slot=missing\"; \\
    [ -d \"$G/guests/$slot/rootfs\" ] || [ -n \"\$id\" ] || { [ -d \"$G/guest\" ] && echo \"legacy=yes\"; }; \\
    $G/lxc/bin/lxc-info -P $G -n guest 2>/dev/null | grep -q RUNNING && echo \"guest=running\" || echo \"guest=stopped\"'" | tr -d '\r')

current=$(printf '%s\n' "$remote_check" | sed -n 's/^current=//p')
state_slot=$(printf '%s\n' "$remote_check" | sed -n 's/^slot=//p')
state_guest=$(printf '%s\n' "$remote_check" | sed -n 's/^guest=//p')
legacy=$(printf '%s\n' "$remote_check" | sed -n 's/^legacy=//p')

echo "phone:      $serial"
echo "current:    ${current:-<none>}"
[ -n "$legacy" ] && echo "layout:     legacy direct rootfs ($G/guest) - no slots installed yet"
echo "target:     $slot"
echo "slot state: $state_slot"
echo "guest:      $state_guest"

stop_note=
[ "$state_guest" = running ] && stop_note="  [running] "
cat <<EOF

plan:
  1.${stop_note:+$stop_note}lxc-stop -P $G -n guest            # stop the container first
  2. cp $G/active-guest $G/active-guest.bak       # preserve current pointer
  3. printf '%s\\n' '$slot' > $G/active-guest.tmp &&
     mv $G/active-guest.tmp $G/active-guest       # atomic pointer swap
  4. $G/bin/guest-distro select $slot             # re-provision hooks
  5. review, then optionally: $G/bin/guest-start  # restart into $slot
EOF

[ "$state_slot" = ok ] || { echo "refusing: slot '$slot' has no rootfs on device" >&2; exit 1; }

if [ "$execute" != true ]; then
    echo
    echo "dry-run complete. re-run with --execute to apply." >&2
    exit 0
fi

printf 'Apply rollback to "%s"? type YES: ' "$slot"
read -r answer
[ "$answer" = YES ] || { echo "aborted" >&2; exit 1; }

stop_step=
[ "$state_guest" = running ] && stop_step="$G/lxc/bin/lxc-stop -P $G -n guest;"
# One quoted su -c chain (AGENTS.md quoting rule).
adb shell "su -c '${stop_step}cp $G/active-guest $G/active-guest.bak 2>/dev/null; \\
    printf \"%s\\\\n\" \"$slot\" > $G/active-guest.tmp && mv $G/active-guest.tmp $G/active-guest && \\
    $G/bin/guest-distro select $slot'" </dev/null

echo "rollback applied: active-guest=$slot (previous saved as active-guest.bak)"
echo "next: start the guest, e.g. det shell then $G/bin/guest-start"
