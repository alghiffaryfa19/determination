#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./install.sh [--restart] [--no-deps] [--no-hyprland]

Install Opal into ~/.config/quickshell/opal and install the `opal` command
into ~/.local/bin. Existing shell files are moved to a timestamped backup;
preferences under ~/.local/state/opal are never touched.

Options:
  --restart      reload the running Opal shell after installation
  --no-deps      do not install missing runtime dependencies
  --no-hyprland  do not add the reversible Lua hook to Hyprland
  --help         show this help
EOF
}

restart=0
install_deps=1
install_hyprland=1
for arg in "$@"; do
    case "$arg" in
        --restart) restart=1 ;;
        --no-deps) install_deps=0 ;;
        --no-hyprland) install_hyprland=0 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

source_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_dir="${OPAL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/opal}"
bin_dir="${OPAL_BIN_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/opal"
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$state_dir/pre-deploy-$timestamp-install"
config_parent=$(dirname -- "$config_dir")
hypr_config="${OPAL_HYPRLAND_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"

if [[ ! -f "$source_dir/shell.qml" || ! -f "$source_dir/qmldir" || ! -f "$source_dir/backend.py" ]]; then
    echo "This does not look like an Opal source directory: $source_dir" >&2
    exit 1
fi

install_dependencies() {
    local manager package tool missing_quickshell=0
    local -a missing=() packages=()
    local -A package_for=(
        [quickshell]=quickshell [python3]=python [hyprctl]=hyprland
        [wpctl]=wireplumber [playerctl]=playerctl [nmcli]=networkmanager
        [bluetoothctl]=bluez [brightnessctl]=brightnessctl
        [powerprofilesctl]=power-profiles-daemon [grim]=grim
        [wl-copy]=wl-clipboard [notify-send]=libnotify
    )

    for tool in "${!package_for[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    ((${#missing[@]})) || return 0

    if command -v pacman >/dev/null 2>&1; then
        manager=pacman
        for tool in "${missing[@]}"; do packages+=("${package_for[$tool]}"); done
    elif command -v dnf >/dev/null 2>&1; then
        manager=dnf
        for tool in "${missing[@]}"; do packages+=("${package_for[$tool]}"); done
    elif command -v apt-get >/dev/null 2>&1; then
        manager=apt
        for tool in "${missing[@]}"; do
            case "$tool" in
                quickshell) missing_quickshell=1 ;;
                python3) packages+=(python3) ;;
                hyprctl) packages+=(hyprland) ;;
                wpctl) packages+=(wireplumber) ;;
                nmcli) packages+=(network-manager) ;;
                notify-send) packages+=(libnotify-bin) ;;
                *) packages+=("${package_for[$tool]}") ;;
            esac
        done
    else
        echo "Missing dependencies: ${missing[*]}" >&2
        echo "No supported package manager found (pacman, dnf, apt-get)." >&2
        return 1
    fi

    if ((${#packages[@]} == 0)); then
        if [[ "$missing_quickshell" -eq 1 ]]; then
            echo "Quickshell is not available from standard apt repositories. Install it from its official package source, then rerun this script." >&2
            return 1
        fi
        return 0
    fi
    echo "Installing missing Opal dependencies: ${packages[*]}"
    case "$manager" in
        pacman) sudo pacman -S --needed --noconfirm "${packages[@]}" ;;
        dnf) sudo dnf install -y "${packages[@]}" ;;
        apt) sudo apt-get update && sudo apt-get install -y "${packages[@]}" ;;
    esac
    if [[ "$missing_quickshell" -eq 1 ]]; then
        echo "Quickshell is not available from standard apt repositories. Install it from its official package source, then rerun this script." >&2
        return 1
    fi
}

install_hyprland_hook() {
    local hook_path temp hook_escaped
    if [[ ! -f "$hypr_config" ]]; then
        echo "Hyprland Lua config not found at $hypr_config; skipped automatic hook." >&2
        echo "Set OPAL_HYPRLAND_CONFIG to your hyprland.lua path and rerun if needed." >&2
        return 0
    fi
    if grep -Fq "$config_dir/hyprland.lua" "$hypr_config"; then
        echo "Hyprland hook is already installed in $hypr_config"
        return 0
    fi

    mkdir -p "$backup_dir"
    cp -a -- "$hypr_config" "$backup_dir/$(basename -- "$hypr_config").before-opal"
    hook_path="$config_dir/hyprland.lua"
    hook_escaped=${hook_path//\\/\\\\}
    hook_escaped=${hook_escaped//\"/\\\"}
    temp=$(mktemp "${hypr_config}.opal.XXXXXX")
    cp -- "$hypr_config" "$temp"
    {
        printf '\n-- OPAL_INSTALL_HOOK_BEGIN\n'
        printf 'do\n'
        printf '    local marker = io.open((os.getenv("XDG_RUNTIME_DIR") or "/run/user/1000") .. "/opal-active", "r")\n'
        printf '    if marker then\n'
        printf '        marker:close()\n'
        printf '        dofile("%s")\n' "$hook_escaped"
        printf '    end\n'
        printf 'end\n'
        printf '%s\n' '-- OPAL_INSTALL_HOOK_END'
    } >> "$temp"
    mv -- "$temp" "$hypr_config"
    echo "Added reversible Opal hook to $hypr_config"
}

if [[ "$install_deps" -eq 1 ]]; then
    install_dependencies
fi

mkdir -p "$config_parent" "$bin_dir" "$state_dir"
tmp_dir=$(mktemp -d "$config_parent/.opal-install.XXXXXX")
old_dir=""
cleanup() {
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

# Copy only the source package. Git metadata, tests, bytecode, and local
# recovery directories never become part of the live shell installation.
while IFS= read -r -d '' file; do
    install -m 0644 "$file" "$tmp_dir/$(basename -- "$file")"
done < <(find "$source_dir" -maxdepth 1 -type f ! -name '*.pyc' -print0)

if [[ -e "$config_dir" ]]; then
    mkdir -p "$backup_dir"
    mv -- "$config_dir" "$backup_dir/opal"
    old_dir="$backup_dir/opal"
fi

if ! mv -- "$tmp_dir" "$config_dir"; then
    if [[ -n "$old_dir" && ! -e "$config_dir" ]]; then
        mv -- "$old_dir" "$config_dir"
    fi
    echo "Could not activate the new Opal installation; the previous copy was restored." >&2
    exit 1
fi

wrapper_tmp=$(mktemp "$bin_dir/.opal.XXXXXX")
cat > "$wrapper_tmp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

config="${OPAL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/opal}"
marker="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/opal-active"

systemd_user() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user "$@"
}

case "${1:-on}" in
    on)
        quickshell -d -n -p "$config"
        systemd_user mask --runtime --now dms.service || true
        touch "$marker"
        command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && hyprctl reload config-only || true
        echo 'Opal is on. Return to DMS with: opal off'
        ;;
    reload)
        quickshell kill -p "$config" || true
        # Quickshell releases a detached instance asynchronously. Starting in
        # the same instant can be rejected as an already-running config.
        sleep 1
        exec "$0" on
        ;;
    off)
        rm -f -- "$marker"
        quickshell kill -p "$config" || true
        systemd_user unmask --runtime dms.service || true
        systemd_user start dms.service || true
        command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && hyprctl reload config-only || true
        ;;
    console|gaming)
        exec quickshell ipc -p "$config" call opal gaming
        ;;
    launcher|controls|notifications|clipboard|phone|desktop|appearance|close|inspect)
        exec quickshell ipc -p "$config" call opal "$1"
        ;;
    *)
        echo 'Usage: opal [on|reload|off|launcher|controls|notifications|clipboard|phone|console|gaming|desktop|appearance|close|inspect]' >&2
        exit 2
        ;;
esac
EOF
chmod 0755 "$wrapper_tmp"
mv -- "$wrapper_tmp" "$bin_dir/opal"

if [[ "$install_hyprland" -eq 1 ]]; then
    install_hyprland_hook
fi

if [[ "$restart" -eq 1 ]]; then
    "$bin_dir/opal" reload
fi

echo "Installed Opal to $config_dir"
echo "Installed command to $bin_dir/opal"
[[ -n "$old_dir" ]] && echo "Previous shell backed up at $old_dir"
echo "Run '$bin_dir/opal on' to start it, or '$bin_dir/opal reload' to reload it."
