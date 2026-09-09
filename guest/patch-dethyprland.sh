#!/bin/sh
set -eu
SRC=${1:-/root/build/dethyprland}
PATCHES=${2:-/root/dethyprland/patches}
apply() {
    project=$1 rev=$2 patch=$3
    [ "$(git -C "$SRC/$project" rev-parse HEAD)" = "$rev" ] || {
        echo "refusing unexpected $project revision" >&2; exit 2;
    }
    if git -C "$SRC/$project" apply --reverse --check "$PATCHES/$patch" 2>/dev/null; then
        return
    fi
    git -C "$SRC/$project" apply --check "$PATCHES/$patch"
    git -C "$SRC/$project" apply "$PATCHES/$patch"
}
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-native-buffer.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-vendor-egl.patch
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-gralloc-hwc.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-hybris-backend.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-native-output.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-socket.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-optional-dmabuf.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-android-wlegl.patch
mkdir -p "$SRC/Hyprland/src/dethyprland"
cp "$PATCHES/../AndroidWlegl.cpp" "$PATCHES/../wayland-android.xml" \
    "$SRC/Hyprland/src/dethyprland/"
mkdir -p "$SRC/aquamarine/src/dethyprland"
cp "$PATCHES/../HybrisBuffer.cpp" "$PATCHES/../HybrisBuffer.hpp" \
    "$PATCHES/../AquamarineBuffer.hpp" "$PATCHES/../GrallocAllocator.hpp" \
    "$PATCHES/../HwcPresenter.hpp" "$SRC/aquamarine/src/dethyprland/"
