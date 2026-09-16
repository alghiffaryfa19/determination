#!/bin/sh
# Install the generic Linux application contracts expected by modern GNOME,
# GTK, Qt and sandboxed apps. Run as root inside a networked guest.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ ! -f /usr/local/lib/aurora-pidfd-shim.so ] || \
    export LD_PRELOAD=/usr/local/lib/aurora-pidfd-shim.so

[ "$(id -u)" -eq 0 ] || { echo 'run setup-compatibility.sh as root' >&2; exit 1; }
platform=$(aurora-platform id 2>/dev/null || echo debian)
install_packages() {
    for package in "$@"; do
        aurora-platform package-install "$package"
    done
}

aurora-platform package-refresh
case "$platform" in
    debian)
        install_packages \
            xdg-desktop-portal xdg-desktop-portal-phosh xdg-desktop-portal-gtk xdg-utils xdg-user-dirs \
            dbus-user-session gnome-keyring libpam-gnome-keyring at-spi2-core \
            gvfs gvfs-backends flatpak gnome-software-plugin-flatpak \
            desktop-file-utils shared-mime-info libnotify-bin \
            fonts-noto-core fonts-noto-color-emoji
        ;;
    arch)
        install_packages \
            xdg-desktop-portal xdg-desktop-portal-phosh xdg-desktop-portal-gtk xdg-utils xdg-user-dirs \
            gnome-keyring at-spi2-core gvfs flatpak noto-fonts noto-fonts-emoji
        ;;
    alpine)
        # Alpine remains experimental. Keep package failures visible because a
        # silent partial portal stack is worse than an honest unqualified one.
        install_packages \
            xdg-desktop-portal xdg-desktop-portal-phosh xdg-desktop-portal-gtk xdg-utils xdg-user-dirs \
            gnome-keyring at-spi2-core gvfs flatpak font-noto font-noto-emoji
        ;;
    *) echo "unsupported guest profile: $platform" >&2; exit 2 ;;
esac

install -d -m 0755 /etc/xdg/xdg-desktop-portal
cat > /etc/xdg/xdg-desktop-portal/phosh-portals.conf <<'EOF'
[preferred]
default=phosh;gtk;
org.freedesktop.impl.portal.FileChooser=phosh;gtk;
org.freedesktop.impl.portal.Screenshot=phosh;
org.freedesktop.impl.portal.ScreenCast=phosh;
EOF

install -d -m 0755 /etc/environment.d
cat > /etc/environment.d/90-aurora-session.conf <<'EOF'
# Static app-selection hints. Display addresses and renderer library paths are
# injected by aurora-phosh-session because they are session-specific.
XDG_CURRENT_DESKTOP=Phosh:GNOME
XDG_SESSION_DESKTOP=phosh
DESKTOP_SESSION=phosh
GDK_BACKEND=wayland,x11
QT_QPA_PLATFORM=wayland
MOZ_ENABLE_WAYLAND=1
GTK_USE_PORTAL=1
EOF

if [ "$platform" = debian ] || [ "$platform" = arch ]; then
    install -D -m 0644 /usr/local/lib/aurora/aurora-phosh.service \
        /etc/systemd/system/aurora-phosh.service
    systemctl daemon-reload
fi

# Create standard folders and MIME state as the actual desktop user.
aurora-platform run-user aurora env HOME=/home/aurora USER=aurora LOGNAME=aurora \
    xdg-user-dirs-update
update-desktop-database /usr/share/applications 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true

echo "SETUP-COMPATIBILITY-OK profile=$platform"
