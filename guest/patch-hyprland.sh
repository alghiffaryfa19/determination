#!/bin/sh
set -eu
SRC=${1:-/root/build/hyprland}
PATCHES=${2:-/root/hyprland/patches}
STAMP=$SRC/.aurora-patches-stamp
# Several patches touch the same files (Backend.cpp/Headless.cpp), so
# reverse-check idempotency cannot work: reversing one patch against a tree
# carrying the others fails context. Track applied patches in a stamp file
# instead; the pinned-revision check below still guards every entry.
stamped() { grep -qx "$1" "$STAMP" 2>/dev/null; }
apply() {
    project=$1 rev=$2 patch=$3
    [ "$(git -C "$SRC/$project" rev-parse HEAD)" = "$rev" ] || {
        echo "refusing unexpected $project revision" >&2; exit 2;
    }
    if stamped "$project/$patch"; then
        return
    fi
    if git -C "$SRC/$project" apply --reverse --check "$PATCHES/$patch" 2>/dev/null; then
        echo "$project/$patch" >> "$STAMP"
        return
    fi
    git -C "$SRC/$project" apply --check "$PATCHES/$patch"
    git -C "$SRC/$project" apply "$PATCHES/$patch"
    echo "$project/$patch" >> "$STAMP"
}
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-native-buffer.patch
apply hyprutils 674ea57373f08b7609ce93baff131117a0dfe70d hyprutils-cstdint.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-vendor-egl.patch
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-gralloc-hwc.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-hybris-backend.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-native-output.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-socket.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-optional-dmabuf.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-android-wlegl.patch
apply Hyprland 9958d297641b5c84dcff93f9039d80a5ad37ab00 hyprland-climits.patch
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-producer-fence.patch
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-buffer-commit.patch
apply aquamarine a19cf76ee1a15c1c12083fa372747ce46387289f aquamarine-hybris-input.patch
mkdir -p "$SRC/Hyprland/src/hyprland"
cp "$PATCHES/../AndroidWlegl.cpp" "$PATCHES/../wayland-android.xml" \
    "$SRC/Hyprland/src/hyprland/"
mkdir -p "$SRC/aquamarine/src/hyprland"
cp "$PATCHES/../HybrisBuffer.cpp" "$PATCHES/../HybrisBuffer.hpp" \
    "$PATCHES/../AquamarineBuffer.hpp" "$PATCHES/../GrallocAllocator.hpp" \
    "$PATCHES/../HwcPresenter.hpp" "$SRC/aquamarine/src/hyprland/"
