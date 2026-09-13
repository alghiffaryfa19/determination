#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/usr/bin" "$WORK/root/etc"
touch "$WORK/root/usr/bin/sh"
printf 'untouched\n' > "$WORK/resolver"
ln -s "$WORK/resolver" "$WORK/root/etc/resolv.conf"
"$REPO/guest/customize-portable-rootfs.sh" "$WORK/root" arch
[ ! -L "$WORK/root/etc/resolv.conf" ]
grep -qx untouched "$WORK/resolver"
grep -q '^nameserver ' "$WORK/root/etc/resolv.conf"
[ "$(readlink "$WORK/root/etc/systemd/system/systemd-networkd.service")" = /dev/null ]
grep -qx 'PasswordAuthentication no' "$WORK/root/etc/ssh/sshd_config.d/00-determination.conf"
grep -q 'pacman-key --populate archlinuxarm' "$WORK/root/root/determination-firstboot"
[ ! -e "$WORK/root/etc/determination-ready" ]
[ "$(stat -c %a "$WORK/root/tmp")" = 1777 ]
sh -n "$WORK/root/root/determination-firstboot"
echo 'portable rootfs tests passed'
