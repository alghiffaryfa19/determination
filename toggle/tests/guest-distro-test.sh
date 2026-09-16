#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
REAL_TAR=$(command -v tar)
mkdir -p "$WORK/bin" "$WORK/etc" "$WORK/guest/etc" "$WORK/guest/sbin" \
    "$WORK/lxc/bin" "$WORK/run" "$WORK/archive/etc" "$WORK/archive/sbin" \
    "$WORK/toybox-bin"
printf '13\n' > "$WORK/guest/etc/debian_version"
printf '#!/bin/sh\n' > "$WORK/guest/sbin/init"
chmod 0755 "$WORK/guest/sbin/init"
cp "$ROOT/toggle/guest-distro" "$WORK/bin/guest-distro"

cat > "$WORK/lxc/bin/lxc-info" <<EOF
#!/bin/sh
[ -e "$WORK/run/fake-running" ] && echo 'State: RUNNING' || echo 'State: STOPPED'
EOF
cat > "$WORK/lxc/bin/lxc-stop" <<EOF
#!/bin/sh
rm -f "$WORK/run/fake-running"
EOF
cat > "$WORK/lxc/bin/lxc-attach" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$WORK/bin/guest-start" <<EOF
#!/bin/sh
id=\$(sh "$WORK/bin/guest-distro" active)
[ ! -e "$WORK/run/fail-\$id" ] || exit 1
touch "$WORK/run/fake-running"
EOF
chmod 0755 "$WORK/bin/"* "$WORK/lxc/bin/"*

# Android toybox appends ` -> target` to symlinks in plain tar listings. Keep
# the real extractor, but reproduce that listing dialect so host tests cover
# the parser used on the phone.
cat > "$WORK/toybox-bin/tar" <<EOF
#!/bin/sh
if [ "\${1:-}" = -tzf ]; then
    "$REAL_TAR" "\$@"
    echo './compat-link -> ../../../etc'
else
    exec "$REAL_TAR" "\$@"
fi
EOF
chmod 0755 "$WORK/toybox-bin/tar"

AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" sh "$WORK/bin/guest-distro" ensure
[ "$(readlink "$WORK/active-guest")" = guest ]
[ "$(AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" sh "$WORK/bin/guest-distro" active)" = debian ]

cat > "$WORK/archive/etc/aurora-profile" <<'EOF'
ID=arch
NAME=Arch Linux ARM
LIBC=glibc
INIT=systemd
CONTRACT=1
EOF
printf '#!/bin/sh\n' > "$WORK/archive/sbin/init"
chmod 0755 "$WORK/archive/sbin/init"
tar -C "$WORK/archive" -czf "$WORK/arch.tar.gz" .
PATH="$WORK/toybox-bin:$PATH" AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" \
    sh "$WORK/bin/guest-distro" install arch "$WORK/arch.tar.gz"
AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" sh "$WORK/bin/guest-distro" select arch
[ "$(AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" sh "$WORK/bin/guest-distro" active)" = arch ]
[ "$(readlink "$WORK/active-guest")" = guests/arch/rootfs ]

mkdir -p "$WORK/guests/alpine/rootfs/etc" "$WORK/guests/alpine/rootfs/sbin"
cat > "$WORK/guests/alpine/rootfs/etc/aurora-profile" <<'EOF'
ID=alpine
NAME=Alpine Linux
LIBC=musl
INIT=openrc
CONTRACT=1
EOF
printf '#!/bin/sh\n' > "$WORK/guests/alpine/rootfs/sbin/init"
chmod 0755 "$WORK/guests/alpine/rootfs/sbin/init"
touch "$WORK/run/fail-alpine"
if AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" sh "$WORK/bin/guest-distro" select alpine; then
    echo "expected Alpine health-gate failure" >&2
    exit 1
fi
[ "$(AURORA="$WORK" AURORA_LXC_BIN="$WORK/lxc/bin" sh "$WORK/bin/guest-distro" active)" = arch ]
[ -e "$WORK/run/fake-running" ]

# A phone that chooses Arch/Alpine first still needs a config-only
# $AURORA/guest anchor for LXC. Installing Debian later must replace only that
# empty anchor, retain its config, and never mistake it for an installed slot.
FRESH="$WORK/fresh"
mkdir -p "$FRESH/bin" "$FRESH/guest" "$FRESH/debian-archive/etc" \
    "$FRESH/debian-archive/sbin" "$FRESH/lxc/bin"
cp "$ROOT/toggle/guest-distro" "$FRESH/bin/guest-distro"
printf 'lxc.rootfs.path = dir:/data/aurora/active-guest\n' > "$FRESH/guest/config"
cat > "$FRESH/debian-archive/etc/os-release" <<'EOF'
ID=debian
PRETTY_NAME="Debian GNU/Linux"
EOF
printf '13\n' > "$FRESH/debian-archive/etc/debian_version"
printf '#!/bin/sh\n' > "$FRESH/debian-archive/sbin/init"
chmod 0755 "$FRESH/debian-archive/sbin/init"
tar -C "$FRESH/debian-archive" -czf "$FRESH/debian.tar.gz" .
AURORA="$FRESH" AURORA_LXC_BIN="$FRESH/lxc/bin" \
    sh "$FRESH/bin/guest-distro" install debian "$FRESH/debian.tar.gz"
[ -f "$FRESH/guest/etc/os-release" ]
[ -f "$FRESH/guest/config" ]
AURORA="$FRESH" AURORA_LXC_BIN="$FRESH/lxc/bin" \
    sh "$FRESH/bin/guest-distro" activate debian
[ "$(readlink "$FRESH/active-guest")" = guest ]

echo "guest distro tests passed"
