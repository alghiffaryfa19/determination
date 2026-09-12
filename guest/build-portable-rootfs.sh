#!/bin/sh
# Build Arch Linux ARM or Alpine Aurora rootfs archives without running
# foreign-architecture binaries. Package/user provisioning happens on first LXC
# boot through /root/aurora-firstboot.

set -eu
[ "$(id -u)" -eq 0 ] || {
    echo "run inside a rootless user namespace: podman unshare $0 $*" >&2
    exit 1
}
CALLER_DIR=$PWD
cd "$(dirname "$0")"

PROFILE=${1:-}
SOURCE=${2:-}
case "$SOURCE" in ''|/*) ;; *) SOURCE=$CALLER_DIR/$SOURCE ;; esac
OUT=${OUT:-}
ALPINE_VERSION=${ALPINE_VERSION:-3.24.0}
ALPINE_SHA256=${ALPINE_SHA256:-4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a}
ALARM_KEY=${ALARM_KEY:-68B3537F39A313B3E574D06777193F152BDBE6A6}

case "$PROFILE" in
    arch)
        OUT=${OUT:-aurora-rootfs-arch.tar.gz}
        URL=${ALARM_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
        ;;
    alpine)
        OUT=${OUT:-aurora-rootfs-alpine.tar.gz}
        URL=https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-minirootfs-$ALPINE_VERSION-aarch64.tar.gz
        ;;
    *) echo "usage: $0 arch|alpine [source-tarball]" >&2; exit 2 ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
ROOT="$WORK/rootfs"
mkdir -p "$ROOT"

if [ -z "$SOURCE" ]; then
    SOURCE="$WORK/source.tar.gz"
    command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
    curl -fL "$URL" -o "$SOURCE"
fi
[ -r "$SOURCE" ] || { echo "source archive not readable: $SOURCE" >&2; exit 1; }

if [ "$PROFILE" = alpine ]; then
    printf '%s  %s\n' "$ALPINE_SHA256" "$SOURCE" | sha256sum -c -
else
    SIG=${SOURCE}.sig
    if [ ! -r "$SIG" ]; then
        [ "$SOURCE" = "$WORK/source.tar.gz" ] || {
            echo "Arch source needs its detached signature beside it: $SIG" >&2
            exit 1
        }
        curl -fL "$URL.sig" -o "$SIG"
    fi
    command -v gpg >/dev/null 2>&1 || { echo "gpg is required for Arch Linux ARM" >&2; exit 1; }
    fingerprint=$(gpg --with-colons --fingerprint "$ALARM_KEY" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
    [ "$fingerprint" = "$ALARM_KEY" ] || {
        echo "import and verify the official Arch Linux ARM signing key first: $ALARM_KEY" >&2
        exit 1
    }
    gpg --batch --no-autostart --status-fd 1 --verify "$SIG" "$SOURCE" > "$WORK/signature.status"
    awk -v key="$ALARM_KEY" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && ($3 == key || $12 == key) { valid=1 } END { exit !valid }' \
        "$WORK/signature.status" || { echo "archive signer is not $ALARM_KEY" >&2; exit 1; }
fi

tar --delay-directory-restore -xzf "$SOURCE" -C "$ROOT"
./customize-portable-rootfs.sh "$ROOT" "$PROFILE"
source_hash=$(sha256sum "$SOURCE" | awk '{print $1}')
printf '%s\n' "$source_hash" > "$ROOT/etc/aurora-source-sha256"

tar --numeric-owner -C "$ROOT" -czf "$OUT" .
echo "Rootfs: $OUT"
echo "Install: aurora distro install $PROFILE $OUT"
echo "Then:    aurora distro select $PROFILE && aurora distro provision"
