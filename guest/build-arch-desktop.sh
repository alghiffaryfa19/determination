#!/bin/sh
# Cross-compile the vendor graphics stack against signed Arch ARM packages.
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if [ "${1:-}" != --inside ]; then
    BUILD=${AURORA_BUILD_ROOT:-$REPO/build}
    mkdir -p "$BUILD"
    IMAGE=${AURORA_ARCH_DESKTOP_IMAGE:-localhost/aurora/arch-desktop-cross:trixie}
    if ! podman image exists "$IMAGE"; then
        podman build -t "$IMAGE" -f "$REPO/guest/Containerfile.arch-desktop" "$REPO"
    fi
    exec podman run --rm -v "$REPO:/work:ro" -v "$BUILD:/build" \
        -e AURORA_BUILD_ROOT=/build -w /work "$IMAGE" sh guest/build-arch-desktop.sh --inside
fi
. "$REPO/guest/sources.lock"
WORK=${AURORA_BUILD_ROOT:-$REPO/build}/arch-desktop
ROOT=$WORK/sysroot
B=$WORK/sources
JOBS=${AURORA_BUILD_JOBS:-6}
export PKG_CONFIG_SYSROOT_DIR=$ROOT
export PKG_CONFIG_LIBDIR=$ROOT/usr/local/lib/pkgconfig:$ROOT/usr/lib/pkgconfig:$ROOT/usr/share/pkgconfig
export PKG_CONFIG_PATH=
export WAYLAND_SCANNER=/usr/bin/wayland-scanner
export CC="aarch64-linux-gnu-gcc --sysroot=$ROOT"
export CXX="aarch64-linux-gnu-g++ --sysroot=$ROOT"
export LDFLAGS="-L$ROOT/usr/local/lib -L$ROOT/usr/lib -Wl,-rpath-link,$ROOT/usr/local/lib -Wl,-rpath-link,$ROOT/usr/lib"
mkdir -p "$B" "$WORK/build" "$WORK/headers"
python3 - "$REPO/guest/arch-desktop-cross.ini" "$WORK/cross.ini" "$WORK" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text().replace('/work/build/arch-desktop', sys.argv[3]))
PY
if [ ! -f "$ROOT/usr/include/android/android-version.h" ]; then
    curl -fL "$ANDROID_HEADERS_30_URL" -o "$WORK/headers/android.deb"
    printf '%s  %s\n' "$ANDROID_HEADERS_30_SHA256" "$WORK/headers/android.deb" | sha256sum -c -
    (cd "$WORK/headers" && ar x android.deb && tar -xf data.tar.* -C "$ROOT")
fi
clone_pin() {
    url=$1 pin=$2 name=$3
    if [ ! -d "$B/$name/.git" ]; then
        git init "$B/$name"
        git -C "$B/$name" remote add origin "$url"
        git -C "$B/$name" fetch --depth 1 origin "$pin"
        git -C "$B/$name" checkout --detach FETCH_HEAD
    fi
    [ "$(git -C "$B/$name" rev-parse HEAD)" = "$pin" ] || {
        echo "Unexpected source revision: $name" >&2; exit 1;
    }
}
clone_pin "$LIBGLIBUTIL_REPO" "$LIBGLIBUTIL_COMMIT" libglibutil
clone_pin "$LIBGBINDER_REPO" "$LIBGBINDER_COMMIT" libgbinder
for name in libglibutil libgbinder; do
    make -C "$B/$name" -j"$JOBS" CC="$CC" AR=aarch64-linux-gnu-ar STRIP=aarch64-linux-gnu-strip release pkgconfig
    make -C "$B/$name" CC="$CC" AR=aarch64-linux-gnu-ar STRIP=aarch64-linux-gnu-strip DESTDIR="$ROOT" install-dev
done
if [ ! -f "$B/libhybris/hybris/configure.ac" ]; then
    AURORA_PREPARE_ONLY=1 SRC="$B/libhybris" sh "$REPO/guest/build-libhybris.sh"
fi
if [ ! -f "$B/phoc/meson.build" ]; then
    AURORA_PREPARE_ONLY=1 B="$B" sh "$REPO/guest/build-wlroots-phoc.sh"
fi
(
    cd "$B/libhybris/hybris"
    [ -x configure ] || NOCONFIGURE=1 ./autogen.sh
    ./configure --build="$(./config.guess)" --host=aarch64-linux-gnu \
        --prefix=/usr/local --enable-arch=arm64 \
        --with-android-headers="$ROOT/usr/include/android" \
        --with-default-egl-platform=hwcomposer --enable-wayland \
        --enable-adreno-quirks --enable-experimental
    make -C platforms/common -B wayland-android-client-protocol.h wayland-android-server-protocol.h wayland-android-protocol.c
    for dir in include common properties hardware ui gralloc libsync platforms egl glesv1 glesv2 hwc2; do
        make -C "$dir" -j"$JOBS"
        make -C "$dir" DESTDIR="$ROOT" install
    done
)
build_meson() {
    name=$1; shift
    env -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u CC -u CXX -u LDFLAGS meson setup --clearcache --reconfigure "$WORK/build/$name" "$B/$name" \
        --cross-file "$WORK/cross.ini" \
        --prefix=/usr/local --libdir=lib --buildtype=release --wrap-mode=nofallback "$@"
    ninja -C "$WORK/build/$name" -j"$JOBS"
    DESTDIR="$ROOT" meson install -C "$WORK/build/$name" --no-rebuild
}
python3 - "$B/libdroid/include/libdroid/meson.build" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if 'if not meson.is_cross_build()' not in s:
    start = s.index("gnome = import('gnome')")
    end = s.index('install_headers', start)
    s = s[:start] + 'if not meson.is_cross_build()\n' + s[start:end] + 'endif\n\n' + s[end:]
    p.write_text(s)
PY
build_meson libdroid
build_meson wlroots -Dbackends=drm,libinput,hwcomposer -Drenderers=gles2,android -Dxwayland=enabled -Dexamples=false
build_meson phoc -Dembed-wlroots=disabled -Dman=false -Dxwayland=enabled -Dtests=false
glib-compile-schemas "$ROOT/usr/share/glib-2.0/schemas"
echo 'Arch vendor graphics cross-build complete'
