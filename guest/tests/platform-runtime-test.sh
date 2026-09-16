#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
set -- id
. "$REPO/guest/aurora-platform" >/dev/null
platform_id() { echo arch; }
pacman() {
    case "$1" in
        -Q) [ "${SYSTEMD_INSTALLED:-yes}" = yes ] ;;
        -S) shift; printf '%s\n' "$@" >> "$WORK/targets" ;;
        *) echo 'unexpected pacman operation' >&2; return 1 ;;
    esac
}
install_deps runtime
! grep -qx systemd "$WORK/targets"
grep -qx seatd "$WORK/targets"
grep -qx xdg-desktop-portal "$WORK/targets"
: > "$WORK/targets"
SYSTEMD_INSTALLED=no
install_deps runtime
[ "$(grep -cx systemd "$WORK/targets")" = 1 ]
SYSTEMD_INSTALLED=yes
for component in runtime wlroots-phoc hyprland quickshell; do
    : > "$WORK/targets"
    install_deps "$component"
    ! grep -Eq '^systemd(-libs|-sysvcompat|-resolvconf)?$' "$WORK/targets"
    [ -s "$WORK/targets" ]
done
: > "$WORK/targets"
package_install systemd systemd-libs systemd-sysvcompat systemd-resolvconf
[ ! -s "$WORK/targets" ]
package_install foot systemd-libs firefox systemd foot
printf '%s\n' --needed --noconfirm foot firefox foot > "$WORK/expected"
cmp "$WORK/expected" "$WORK/targets"
: > "$WORK/targets"
SYSTEMD_INSTALLED=no
package_install systemd systemd-libs systemd-sysvcompat systemd-resolvconf
printf '%s\n' --needed --noconfirm systemd systemd-libs systemd-sysvcompat systemd-resolvconf > "$WORK/expected"
cmp "$WORK/expected" "$WORK/targets"
# Resolving a dependency set must never reach the package manager: the
# installer lists groups to show and to remove.
: > "$WORK/targets"
listed=$(AURORA_DEPS_DRYRUN=1 install_deps runtime)
[ -s "$WORK/targets" ] && { echo 'a dependency listing installed packages' >&2; exit 1; }
printf '%s' "$listed" | grep -q 'seatd' || { echo 'a dependency listing lost a package' >&2; exit 1; }
echo 'All Arch dependency groups and package installs preserve installed init packages'
