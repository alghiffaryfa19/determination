#!/bin/sh
# Aurora guest identity + feedback hardware enablement.
# Run inside the container as root. Idempotent: safe to re-run every upgrade.
#
#  - /etc/os-release: PRETTY_NAME becomes Aurora without touching
#    ID=debian (aurora-platform dispatches packages off ID; never change it).
#  - /etc/aurora.ascii: the soul logo used by fastfetch/hyfetch/MOTD.
#  - feedbackd rumble tag on qti-haptics so phosh taps actually buzz.
set -eu

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VERSION=${1:-unknown}
CODENAME=${2:-Aqua}

[ "$(id -u)" -eq 0 ] || { echo "FATAL: run as root" >&2; exit 1; }

# ---------------------------------------------------------------- logo -----
# The soul. Red heart; terminal colors are applied by whoever prints it.
# Plain cat-write: `install /dev/stdout` has no readable stdout fd under
# lxc-attach (caught live 2026-08-22 - it aborts the whole identity pass
# under set -e).
cat > /etc/aurora.ascii <<'ASCII'
        ██╗   ██╗
        ██║   ██║
        ██║   ██║
        ╚██╗ ██╔╝
         ╚████╔╝
          ╚═══╝
   D E T E R M I N A T I O N
ASCII
chmod 0644 /etc/aurora.ascii

# ------------------------------------------------------------ os-release ---
os=/etc/os-release
touch "$os"
sed -i '/^PRETTY_NAME=/d;/^NAME=/d;/^HOME_URL=/d;/^SUPPORT_URL=/d;/^DOCUMENTATION_URL=/d;/^AURORA_/d' "$os"
{
    echo "NAME=\"Aurora\""
    echo "PRETTY_NAME=\"Aurora $VERSION ($CODENAME)\""
    echo "HOME_URL=\"https://aurora.local\""
    echo "AURORA_VERSION=$VERSION"
    echo "AURORA_CODENAME=$CODENAME"
} >> "$os"
# ID/LIKE/other upstream lines stay above ours; ordering does not matter,
# but keep ID=debian verifiable right here so nobody "fixes" it later.
grep -q '^ID=' "$os" || echo 'ID=debian' >> "$os"

# ------------------------------------------------------------- fastfetch ---
# System config gains the soul logo. User configs override this whole file,
# which is intended.
ff=/etc/xdg/fastfetch/config.jsonc
if [ -d /etc/xdg/fastfetch ] || mkdir -p /etc/xdg/fastfetch; then
    cat > "$ff" <<EOF
{
    "logo": {
        "type": "small",
        "source": "/etc/aurora.ascii",
        "color": {"1": "red"}
    },
    "modules": [
        "title",
        "separator",
        "os",
        "kernel",
        "uptime",
        "packages",
        "shell",
        "terminal",
        "cpu",
        "memory",
        "swap",
        "disk",
        "localip",
        "battery",
        "break",
        "colors"
    ]
}
EOF
fi

# --------------------------------------------------------------- hyfetch ---
if command -v hyfetch >/dev/null 2>&1; then
    # Backend-dependent custom-logo flags differ; detect once per install.
    if command -v fastfetch >/dev/null 2>&1; then
        hf_args='["--logo","/etc/aurora.ascii"]'
    else
        hf_args='["--ascii_file","/etc/aurora.ascii"]'
    fi
    for home in /root /home/*; do
        [ -d "$home" ] || continue
        cfg="$home/.config/hyfetch.json"
        install -d -m 0755 "$(dirname "$cfg")"
        printf '{"preset":"rainbow","backend":"%s","args":%s}\n' \
            "$(command -v fastfetch >/dev/null 2>&1 && echo fastfetch || echo neofetch)" \
            "$hf_args" > "$cfg"
        chown -R "$(stat -c %u:%g "$home")" "$(dirname "$cfg")"
    done
fi

# --------------------------------------------------------------- haptics ---
# feedbackd only drives devices tagged for rumble; qti-haptics ships untagged
# because Android owns it through its own HAL. Tag it, then re-trigger.
rules=/etc/udev/rules.d/70-aurora-feedback.rules
cat > "$rules" <<'EOF'
SUBSYSTEM=="input", ATTRS{name}=="qti-haptics", ENV{ID_INPUT}="1", TAG+="feedbackd:rumble"
EOF
chmod 0644 "$rules"

# ------------------------------------------------------- feedbackd daemon --
# Bare-session guests have no systemd --user to DBus-activate feedbackd, so
# pin it into the XDG autostart path phosh processes. TryExec makes this a
# no-op wherever the package is absent.
pkg_has_fbd() {
    [ -x /usr/libexec/feedbackd ] && return 0
    [ -x /usr/lib/feedbackd ] && return 0
    return 1
}
fbd_bin=$( [ -x /usr/libexec/feedbackd ] && echo /usr/libexec/feedbackd || echo /usr/lib/feedbackd )
if pkg_has_fbd; then
    install -d -m 0755 /etc/xdg/autostart
    cat > /etc/xdg/autostart/aurora-feedbackd.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Aurora Feedback
Comment=haptic feedback bridge for phosh
Exec=$fbd_bin
TryExec=$fbd_bin
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

# Apply the new udev tag immediately (container eudev may not be running).
udevadm control --reload 2>/dev/null || true
udevadm trigger --subsystem-match=input --attr-match=name=qti-haptics 2>/dev/null || true

# ------------------------------------------------------- alert slider ------
# aurora-sliderd decodes the hall-switch KEY_F3 position values the kernel
# driver emits (see guest/aurora-sliderd docstring); autostart it in-session.
if [ -x /usr/local/bin/aurora-sliderd ] && command -v python3 >/dev/null 2>&1; then
    install -d -m 0755 /etc/xdg/autostart
    cat > /etc/xdg/autostart/aurora-sliderd.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Aurora Alert Slider
Comment=decode oplus tri-state switch positions into sound profiles
Exec=/usr/local/bin/aurora-sliderd
TryExec=/usr/local/bin/aurora-sliderd
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

echo "setup-identity: os-release, logo, fetch configs, haptics tag done"
