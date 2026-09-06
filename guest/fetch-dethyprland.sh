#!/bin/sh
# Prepare pinned port sources, never replace the active guest compositor.
set -eu
DEST=${1:-/root/build/dethyprland}
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
# Hyprland v0.54.3 and its flake.lock dependency revisions.
fetch Hyprland 521ece463c4a9d3d128670688a34756805a4328f
fetch aquamarine 5d2cb726b16ee349df443f84b64cff53221b6983
fetch hyprutils e63f3a79334dec49f8eb1691f66f18115df04085
fetch hyprlang 7615ee388de18239a4ab1400946f3d0e498a8186
fetch hyprcursor b62396457b9cfe2ebf24fe05404b09d2a40f8ed7
fetch hyprgraphics 7d63c04b4a2dd5e59ef943b4b143f46e713df804
fetch hyprwayland-scanner 0a692d4a645165eebd65f109146b8861e3a925e7
fetch hyprland-protocols 1cb6db5fd6bb8aee419f4457402fa18293ace917
printf 'Pinned sources ready: %s\nNo session installed or enabled.\n' "$DEST"
