#!/bin/sh
# Prepare pinned port sources, never replace the active guest compositor.
set -eu
DEST=${1:-/root/build/hyprland}
mkdir -p "$DEST"
fetch() {
    name=$1 rev=$2
    dir="$DEST/$name"
    if [ -e "$dir" ]; then
        [ -d "$dir/.git" ] || { echo "not a checkout: $dir" >&2; exit 2; }
        [ -z "$(git -C "$dir" status --porcelain)" ] || {
            echo "preserving local port changes: $dir" >&2; exit 2;
        }
        [ "$(git -C "$dir" rev-parse HEAD)" = "$rev" ] || {
            echo "unexpected revision in $dir; use a fresh destination" >&2; exit 2;
        }
        return
    fi
    git init "$dir"
    git -C "$dir" remote add origin "https://github.com/hyprwm/$name.git"
    git -C "$dir" fetch --depth 1 origin "$rev"
    git -C "$dir" checkout --detach FETCH_HEAD
    [ "$(git -C "$dir" rev-parse HEAD)" = "$rev" ]
}
# v0.49.0 uses Aquamarine and matches trixie's Wayland/xkbcommon development ABI.
fetch Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00
fetch aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f
fetch hyprutils 674ea57373f08b7609ce93baff131117a0dfe70d
fetch hyprlang 557241780c179cf7ef224df392f8e67dab6cef83
fetch hyprcursor ac903e80b33ba6a88df83d02232483d99f327573
fetch hyprgraphics 60754910946b4e2dc1377b967b7156cb989c5873
fetch hyprwayland-scanner 206367a08dc5ac4ba7ad31bdca391d098082e64b
fetch hyprland-protocols 3a5c2bda1c1a4e55cc1330c782547695a93f05b2
git -C "$DEST/Hyprland" submodule update --init --recursive
printf 'Pinned sources ready: %s\nNo session installed or enabled.\n' "$DEST"
