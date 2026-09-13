#!/system/bin/sh
# The PC validates every artifact and retains a verified boot backup before this script runs.
set -eu
stage=$1 distro=$2 hostname=$3 version=$4 display_name=$5
DET=/data/determination
case "$distro" in debian|arch|alpine) ;; *) exit 2 ;; esac
case "$hostname" in ''|*[!a-z0-9-]*) exit 2 ;; esac
case "$version" in ''|*[!0-9]*) exit 2 ;; esac
[ -n "$display_name" ] && [ "${#display_name}" -le 64 ] || exit 2
if printf '%s' "$display_name" | grep -q '[[:cntrl:]:,]'; then
    exit 2
fi
if [ -x "$DET/lxc/bin/lxc-info" ]; then
    [ "$("$DET/lxc/bin/lxc-info" -P "$DET" -n guest -sH)" = STOPPED ]
fi
if [ -d "$DET/versions/$version" ]; then
    [ -x "$DET/bin/guest-distro" ] || { echo 'Existing module version is incomplete.'; exit 1; }
    [ "$(readlink -f "$DET/current")" = "$DET/versions/$version" ] || {
        echo 'This module version exists but is not active. Resolve the existing installation before retrying.'
        exit 1
    }
    echo "Reusing active module version $version."
else
    magisk --install-module "$stage/module"
fi
mkdir -p "$DET/lxc"
runtime="$DET/lxc/bin.new.$$"
mkdir -m 700 "$runtime"
tar -xzf "$stage/runtime" -C "$runtime"
for tool in lxc-start lxc-stop lxc-attach lxc-info lxc-ls lxc-console lxc-execute; do
    [ -f "$runtime/$tool" ] && [ ! -L "$runtime/$tool" ]
    chmod 0755 "$runtime/$tool"
done
"$runtime/lxc-start" --version
previous="$DET/lxc/bin.previous.$$"
[ ! -d "$DET/lxc/bin" ] || mv "$DET/lxc/bin" "$previous"
if ! mv "$runtime" "$DET/lxc/bin"; then
    [ ! -d "$previous" ] || mv "$previous" "$DET/lxc/bin"
    exit 1
fi
inventory=$("$DET/bin/guest-distro" list)
if ! printf '%s\n' "$inventory" | grep -q "^$distro|installed|"; then
    "$DET/bin/guest-distro" install "$distro" "$stage/rootfs"
fi
"$DET/bin/guest-distro" activate "$distro"
root=$("$DET/bin/guest-distro" root)
[ -d "$root/etc" ]
[ -f "$root/etc/passwd" ] || { echo 'Active guest has no passwd database.'; exit 1; }
passwd_new="$root/etc/passwd.new.$$"
export DET_DISPLAY_NAME="$display_name"
if ! awk -F: -v OFS=: '
    $3 == 1000 { $5 = ENVIRON["DET_DISPLAY_NAME"]; found = 1 }
    { print }
    END { if (!found) exit 1 }
' "$root/etc/passwd" > "$passwd_new"; then
    rm -f "$passwd_new"
    echo 'Active guest has no uid-1000 account.'
    exit 1
fi
chmod 0644 "$passwd_new"
mv -f "$passwd_new" "$root/etc/passwd"
printf '%s\n' "$hostname" > "$root/etc/hostname"
printf 'hostname=%s\n' "$hostname" > "$DET/etc/installer.conf.new"
chmod 0600 "$DET/etc/installer.conf.new"
mv "$DET/etc/installer.conf.new" "$DET/etc/installer.conf"
echo "Userspace installed. Previous runtime retained at $previous."
