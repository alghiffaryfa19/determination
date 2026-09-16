#!/bin/sh
# Aurora guest SSH server setup. Run INSIDE the container as root.
#
# Usage: setup-ssh.sh /path/to/authorized-key.pub
#
# Idempotent. Password and root SSH logins stay disabled; ordinary password-
# gated sudo inside the guest is unaffected. The host-side `aurora ssh-setup`
# command supplies the key and installs a direct host route to this private veth.
set -eu

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TMPDIR=/tmp HOME=/root

KEY_FILE=${1:-}
[ "$(id -u)" -eq 0 ] || { echo "FATAL: run as root" >&2; exit 1; }
[ -n "$KEY_FILE" ] && [ -r "$KEY_FILE" ] || {
    echo "usage: $0 /path/to/authorized-key.pub" >&2
    exit 2
}

# Reject private keys, options-bearing authorized_keys entries, and malformed
# input before touching the package manager or sshd. Package hooks may clean
# /tmp, so keep the validated key material in root's private directory.
KEYS=$(mktemp /root/aurora-ssh-keys.XXXXXX)
trap 'rm -f "$KEYS"' EXIT HUP INT TERM
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    set -- $line
    [ "$#" -ge 2 ] || { echo "FATAL: malformed public key" >&2; exit 2; }
    case "$1" in
        ssh-ed25519|ssh-rsa|ecdsa-sha2-*|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
        *) echo "FATAL: unsupported or options-bearing public key: $1" >&2; exit 2 ;;
    esac
    case "$2" in *[!A-Za-z0-9+/=]*) echo "FATAL: malformed public-key data" >&2; exit 2 ;; esac
    printf '%s\n' "$line" >> "$KEYS"
done < "$KEY_FILE"
[ -s "$KEYS" ] || { echo "FATAL: no public keys found" >&2; exit 2; }

echo "== OpenSSH server =="
if [ -x /usr/local/bin/aurora-platform ]; then
    aurora-platform package-refresh
    aurora-platform package-install openssh-server
else
    export DEBIAN_FRONTEND=noninteractive
    dpkg --configure -a 2>/dev/null || true
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends openssh-server
fi

getent passwd aurora >/dev/null || { echo "FATAL: guest user aurora is missing" >&2; exit 1; }
home=$(getent passwd aurora | cut -d: -f6)
group=$(id -gn aurora)
install -d -o aurora -g "$group" -m 0700 "$home/.ssh"
touch "$home/.ssh/authorized_keys"
chown aurora:"$group" "$home/.ssh/authorized_keys"
chmod 0600 "$home/.ssh/authorized_keys"

# Match key type + base64 payload, ignoring comments, so reruns do not append
# duplicates merely because a key's comment changed.
while IFS= read -r line; do
    set -- $line
    if ! awk -v type="$1" -v blob="$2" \
        '$1 == type && $2 == blob { found=1 } END { exit !found }' \
        "$home/.ssh/authorized_keys"; then
        printf '%s\n' "$line" >> "$home/.ssh/authorized_keys"
    fi
done < "$KEYS"

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/50-aurora.conf <<'EOF'
# Aurora: the guest is administered as aurora with a public key.
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AllowUsers aurora
X11Forwarding no
AllowAgentForwarding yes
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel no
EOF

# Alpine's `adduser -D` leaves a `!`-locked shadow entry, and sshd rejects a
# locked account before it considers authorized_keys. Remove only that lock
# after password, keyboard-interactive, and empty-password login are disabled
# above. This creates no usable password; `aurora passwd` can still set one for
# sudo later.
account_state=$(passwd -S aurora 2>/dev/null | awk '{ print $2 }')
case "$account_state" in L|LK) passwd -d aurora >/dev/null ;; esac

ssh-keygen -A
sshd -t
if [ -x /usr/local/bin/aurora-platform ]; then
    aurora-platform service-enable ssh >/dev/null
    aurora-platform service-restart ssh
    aurora-platform service-active ssh || { echo "FATAL: ssh service did not start" >&2; exit 1; }
else
    systemctl enable ssh >/dev/null
    systemctl restart ssh
    systemctl --quiet is-active ssh || { echo "FATAL: ssh.service did not start" >&2; exit 1; }
fi

echo "SSH-SETUP-OK --- key login for aurora; password/root login disabled"
