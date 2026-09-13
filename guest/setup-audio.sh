#!/bin/sh
# Install the guest half of the direct ALSA/PipeWire path. Safe to rerun.
set -eu

[ "$(id -u)" = 0 ] || { echo "run setup-audio.sh as guest root" >&2; exit 1; }
MODE=${1:-install}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

if [ "$MODE" != "--configure-only" ]; then
    apt-get update
    apt-get install -y pipewire pipewire-pulse wireplumber alsa-utils
fi

install -d /etc/pipewire/pipewire.conf.d /usr/local/bin
if [ -f "$HERE/det-audio-session" ]; then
    install -m 0755 "$HERE/det-audio-session" /usr/local/bin/det-audio-session
fi
[ -f "$HERE/90-determination-direct.conf" ] || {
    echo "missing $HERE/90-determination-direct.conf" >&2
    exit 1
}
install -m 0644 "$HERE/90-determination-direct.conf" \
    /etc/pipewire/pipewire.conf.d/90-determination-direct.conf

cat > /etc/profile.d/determination-audio.sh <<'EOF'
# Clients may negotiate larger buffers; this requests a bounded 5.3 ms quantum.
export PIPEWIRE_LATENCY=256/48000
EOF

echo "direct PipeWire configuration installed"
echo "it remains dormant until det-audio-owner publishes audio-claimed"
