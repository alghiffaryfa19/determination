#!/bin/sh
# Read-only libhybris contract gate, except for a display-less gralloc
# allocation which is created and released by the native-handle probe.
#
# This test intentionally never starts or stops SurfaceFlinger, opens the HWC
# platform, changes EGL defaults, or writes into the installed stack.  Run it
# in the guest after libhybris and the Android-side HWC2 compatibility layer
# have been installed.
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
LIBDIR=${DET_LIBHYBRIS_LIBDIR:-/usr/local/lib}
ANDROID_LIBDIR=${DET_LIBHYBRIS_ANDROID_LIBDIR:-/usr/lib/android}
EGL_LIB=${DET_LIBHYBRIS_EGL_LIB:-$LIBDIR/libEGL.so.1}
GLES_LIB=${DET_LIBHYBRIS_GLES_LIB:-$LIBDIR/libGLESv2.so.2}
EGL_BASENAME=$(basename "$EGL_LIB")
HWC_WINDOW_LIB=${DET_LIBHYBRIS_HWC_WINDOW_LIB:-$LIBDIR/libhybris-hwcomposerwindow.so}
WAYLAND_PLUGIN=${DET_LIBHYBRIS_WAYLAND_PLUGIN:-$LIBDIR/libhybris/eglplatform_wayland.so}
MODE_HEADER=${DET_LIBHYBRIS_MODE_HEADER:-/usr/local/include/hybris/hwc2/hwc2_compatibility_layer.h}
MODE_REQUIRED=${DET_LIBHYBRIS_REQUIRE_MODE_API:-${DET_HWC_MODE_API:-0}}
CC_BIN=${CC:-cc}

passes=0
failures=0
skips=0

usage() {
    cat <<'EOF'
Usage: libhybris-contract-test.sh

Checks installed libhybris symbols, the Wayland/HWC EGL split, and a safe
display-less Android native-handle round trip.  HWC mode enumeration is
required when either DET_LIBHYBRIS_REQUIRE_MODE_API=1 or DET_HWC_MODE_API=1.

Useful overrides for staged guests:
  DET_LIBHYBRIS_LIBDIR, DET_LIBHYBRIS_ANDROID_LIBDIR
  DET_LIBHYBRIS_EGL_LIB, DET_LIBHYBRIS_GLES_LIB
  DET_LIBHYBRIS_HWC_WINDOW_LIB, DET_LIBHYBRIS_WAYLAND_PLUGIN
  DET_LIBHYBRIS_MODE_HEADER, DET_LIBHYBRIS_HWC2_LIB
  DET_LIBHYBRIS_SKIP_NATIVE_HANDLE=1 (diagnostic-only escape hatch)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi
[ "${1:-}" = "" ] || {
    printf 'FAIL: unexpected argument: %s\n' "$1" >&2
    usage >&2
    exit 2
}

pass() {
    passes=$((passes + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1" >&2
}

skip() {
    skips=$((skips + 1))
    printf 'SKIP: %s\n' "$1"
}

check_file() {
    file=$1
    description=$2
    if [ -r "$file" ]; then
        pass "$description: $file"
    else
        fail "$description missing or unreadable: $file"
    fi
}

symbol_present() {
    file=$1
    symbol=$2

    if command -v nm >/dev/null 2>&1 &&
        nm -D --defined-only "$file" 2>/dev/null |
        awk -v needle="$symbol" '
            { name = $NF; sub(/@.*/, "", name); if (name == needle) found = 1 }
            END { exit(found ? 0 : 1) }'; then
        return 0
    fi
    if command -v readelf >/dev/null 2>&1 &&
        readelf --dyn-syms --wide "$file" 2>/dev/null |
        awk -v needle="$symbol" '
            $7 != "UND" { name = $8; sub(/@.*/, "", name); if (name == needle) found = 1 }
            END { exit(found ? 0 : 1) }'; then
        return 0
    fi
    return 1
}

check_symbol() {
    file=$1
    symbol=$2
    if [ ! -r "$file" ]; then
        fail "cannot inspect $symbol; library missing: $file"
    elif symbol_present "$file" "$symbol"; then
        pass "$symbol in $(basename "$file")"
    else
        fail "required symbol $symbol is absent from $file"
        if command -v nm >/dev/null 2>&1; then
            printf '      exported candidates:\n' >&2
            nm -D --defined-only "$file" 2>/dev/null |
                awk '{print $NF}' | sed -n '1,80p' >&2 || true
        fi
    fi
}

check_header_symbol() {
    symbol=$1
    if [ ! -r "$MODE_HEADER" ]; then
        fail "HWC mode API header missing: $MODE_HEADER"
    elif grep -F "$symbol" "$MODE_HEADER" >/dev/null 2>&1; then
        pass "$symbol declared by $(basename "$MODE_HEADER")"
    else
        fail "HWC mode API declaration absent: $symbol in $MODE_HEADER"
    fi
}

find_symbol_library() {
    symbol=$1
    explicit=${DET_LIBHYBRIS_HWC2_LIB:-}
    if [ -n "$explicit" ]; then
        [ -r "$explicit" ] && symbol_present "$explicit" "$symbol"
        return $?
    fi

    for file in \
        "$LIBDIR"/libhybris*.so \
        "$LIBDIR"/libhybris*.so.* \
        "$ANDROID_LIBDIR"/libhwc2_compat_layer.so \
        "$ANDROID_LIBDIR"/libhwc2_compat_layer.so.*; do
        [ -r "$file" ] || continue
        if symbol_present "$file" "$symbol"; then
            printf '%s\n' "$file"
            return 0
        fi
    done
    return 1
}

check_mode_symbol() {
    symbol=$1
    mode_library=$(find_symbol_library "$symbol" 2>/dev/null || true)
    if [ -n "$mode_library" ]; then
        pass "$symbol in $(basename "$mode_library")"
    else
        fail "configured HWC mode symbol absent: $symbol"
        printf '      searched %s and %s (set DET_LIBHYBRIS_HWC2_LIB to override)\n' \
            "$LIBDIR" "$ANDROID_LIBDIR" >&2
    fi
}

printf '== Determination libhybris runtime contract ==\n'
printf 'libdir=%s\nandroid-libdir=%s\n\n' "$LIBDIR" "$ANDROID_LIBDIR"

printf '%s\n' '-- installed libraries --'
check_file "$EGL_LIB" 'libEGL'
check_file "$GLES_LIB" 'libGLESv2'
check_file "$HWC_WINDOW_LIB" 'HWC native-window backend'
check_file "$WAYLAND_PLUGIN" 'Wayland EGL platform plugin'

printf '%s\n' '-- required symbols --'
for symbol in \
    eglGetDisplay \
    eglGetPlatformDisplay \
    eglGetProcAddress \
    eglInitialize \
    eglHybrisCreateNativeBuffer \
    eglHybrisReleaseNativeBuffer \
    eglHybrisGetNativeBufferInfo \
    eglHybrisSerializeNativeBuffer \
    eglHybrisCreateRemoteBuffer \
    eglSwapBuffersWithDamageKHR; do
    check_symbol "$EGL_LIB" "$symbol"
done
check_symbol "$GLES_LIB" glShaderSource
for symbol in HWCNativeWindowCreate HWCNativeWindowDestroy HWCNativeWindowSetBufferCount; do
    check_symbol "$HWC_WINDOW_LIB" "$symbol"
done

printf '%s\n' '-- EGL platform separation --'
if [ "${EGL_PLATFORM:-}" = wayland ] &&
    [ "${HYBRIS_EGLPLATFORM:-}" = wayland ]; then
    pass 'current process is configured for client EGL (wayland)'
elif [ -n "${EGL_PLATFORM:-}" ] || [ -n "${HYBRIS_EGLPLATFORM:-}" ]; then
    fail "client EGL environment disagrees: EGL_PLATFORM=${EGL_PLATFORM:-unset} HYBRIS_EGLPLATFORM=${HYBRIS_EGLPLATFORM:-unset}"
else
    skip 'current shell has no client EGL platform; use EGL_PLATFORM=wayland HYBRIS_EGLPLATFORM=wayland for clients'
fi

if [ ! -r "$WAYLAND_PLUGIN" ] || [ ! -r "$HWC_WINDOW_LIB" ]; then
    skip 'cannot compare EGL platform objects until both installed objects exist'
elif [ "$WAYLAND_PLUGIN" != "$HWC_WINDOW_LIB" ] &&
    [ "$(readlink -f "$WAYLAND_PLUGIN" 2>/dev/null || printf '%s' "$WAYLAND_PLUGIN")" != \
       "$(readlink -f "$HWC_WINDOW_LIB" 2>/dev/null || printf '%s' "$HWC_WINDOW_LIB")" ]; then
    pass 'Wayland EGL plugin and HWC window backend are separate installed objects'
else
    fail 'Wayland EGL plugin and HWC window backend collapse to the same object'
fi

if command -v strings >/dev/null 2>&1 &&
    strings "$WAYLAND_PLUGIN" 2>/dev/null | grep -F android_wlegl >/dev/null 2>&1; then
    pass 'Wayland plugin contains the android_wlegl client contract'
elif [ -r "$WAYLAND_PLUGIN" ]; then
    fail "Wayland plugin does not expose an android_wlegl marker: $WAYLAND_PLUGIN"
fi
printf '%s\n' 'required launch split: clients EGL_PLATFORM=wayland; HWC compositor EGL_PLATFORM=hwcomposer'

case "$MODE_REQUIRED" in
    1|yes|true|required)
        printf '%s\n' '-- configured HWC mode API --'
        check_header_symbol hwc2_compat_display_get_configs
        check_header_symbol hwc2_compat_display_set_active_config
        check_mode_symbol hwc2_compat_display_get_configs
        check_mode_symbol hwc2_compat_display_set_active_config
        ;;
    0|no|false|optional|'')
        skip 'HWC mode enumeration API not configured (set DET_LIBHYBRIS_REQUIRE_MODE_API=1 to require it)'
        ;;
    *)
        fail "invalid HWC mode API setting: $MODE_REQUIRED (use 0 or 1)"
        ;;
esac

printf '%s\n' '-- display-less native-handle round trip --'
if [ "${DET_LIBHYBRIS_SKIP_NATIVE_HANDLE:-0}" = 1 ]; then
    skip 'native-handle probe disabled by DET_LIBHYBRIS_SKIP_NATIVE_HANDLE=1'
else
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/libhybris-contract.XXXXXX") || {
        fail 'cannot create a private temporary directory for the native-handle probe'
        WORK=
    }
    if [ -n "$WORK" ]; then
        trap 'rm -rf "$WORK"' EXIT HUP INT TERM
        if [ ! -r "$EGL_LIB" ]; then
            fail "native-handle probe cannot link; exact EGL library is missing: $EGL_LIB"
        elif ! command -v "$CC_BIN" >/dev/null 2>&1; then
            fail "native-handle probe compiler not found: $CC_BIN"
        elif ! "$CC_BIN" -std=c11 -O2 -Wall -Wextra -Werror \
            "$SCRIPT_DIR/libhybris-native-handle-test.c" -o "$WORK/probe" \
            -L"$LIBDIR" -Wl,-rpath,"$LIBDIR" -l:"$EGL_BASENAME"; then
            fail 'native-handle probe failed to compile; inspect compiler output above'
        elif EGL_PLATFORM=null HYBRIS_EGLPLATFORM=null \
            LD_LIBRARY_PATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            HYBRIS_LD_LIBRARY_PATH="${HYBRIS_LD_LIBRARY_PATH:-/usr/lib/android:/vendor/lib64:/system/lib64:/odm/lib64:/apex/com.android.runtime/lib64/bionic}" \
            ANDROID_ROOT=${ANDROID_ROOT:-/system} \
            "$WORK/probe"; then
            pass 'full native_handle serialized and reconstructed without acquiring HWC'
        else
            fail 'display-less native_handle round trip failed; see probe diagnostics above'
        fi
    fi
fi

printf '\nSUMMARY: %d passed, %d failed, %d skipped\n' "$passes" "$failures" "$skips"
if [ "$failures" -ne 0 ]; then
    printf 'Contract is NOT satisfied. Re-run after fixing the first missing library, symbol, or runtime path above.\n' >&2
    exit 1
fi
printf '%s\n' 'Contract is satisfied for the checks that ran.'
