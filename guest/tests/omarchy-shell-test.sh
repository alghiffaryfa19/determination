#!/bin/sh
# Guards the Omarchy shell launch environment and the packaged executable bits.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. The launcher must expose Quickshell's private Qt runtime. Without the
#    prefix on LD_LIBRARY_PATH the shell dies on libQt6Qml*.so.6.
mkdir -p "$WORK/prefix/bin" "$WORK/prefix/lib/compat" "$WORK/prefix/lib"
cat > "$WORK/prefix/bin/quickshell" <<'EOF'
#!/bin/sh
printf 'LD_LIBRARY_PATH=%s\n' "$LD_LIBRARY_PATH" > "$AURORA_TEST_LOG"
printf 'ARGS=%s\n' "$*" >> "$AURORA_TEST_LOG"
EOF
chmod 0755 "$WORK/prefix/bin/quickshell"

mkdir -p "$WORK/home"
AURORA_TEST_LOG="$WORK/log" \
AURORA_DHYPRLAND_PREFIX="$WORK/prefix" \
AURORA_OMARCHY_QUICKSHELL="$WORK/prefix/bin/quickshell" \
AURORA_OMARCHY_PATH="$ROOT/guest/omarchy" \
XDG_RUNTIME_DIR="$WORK/runtime" \
HYPRLAND_INSTANCE_SIGNATURE="omarchy-test" \
HOME="$WORK/home" \
    "$ROOT/guest/aurora-omarchy" start

grep -Fq "LD_LIBRARY_PATH=$WORK/prefix/lib/compat:$WORK/prefix/lib:" "$WORK/log"
grep -Fq "ARGS=-n -p $ROOT/guest/omarchy/shell" "$WORK/log"

# 2. Vendored Omarchy commands are shebang scripts. Every one of them must be
#    executable in the tree the packager consumes.
find "$ROOT/guest/omarchy/bin" -type f | while IFS= read -r f; do
    [ "$(dd if="$f" bs=2 count=1 2>/dev/null)" = '#!' ] || continue
    [ -x "$f" ] || { echo "not executable: $f" >&2; exit 1; }
done

# 3. Module packaging must preserve the mode instead of forcing 0644.
ZIPGEN="$WORK/zipgen.py"
sed -n '/^import os, sys, time, zipfile$/,/^PY$/p' \
    "$ROOT/magisk-module/build-module.sh" | sed '$d' > "$ZIPGEN"
grep -q 'os.stat(path).st_mode' "$ZIPGEN"
mkdir -p "$WORK/fixture/bin"
printf '#!/bin/sh\n' > "$WORK/fixture/bin/tool"
chmod 0755 "$WORK/fixture/bin/tool"
printf 'data\n' > "$WORK/fixture/data.txt"
(cd "$WORK/fixture" && SOURCE_DATE_EPOCH=315532800 python3 "$ZIPGEN" "$WORK/out.zip")
python3 - "$WORK/out.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    tool = z.getinfo('bin/tool').external_attr >> 16
    data = z.getinfo('data.txt').external_attr >> 16
assert tool & 0o111, oct(tool)
assert not data & 0o111, oct(data)
PY

echo 'Omarchy shell tests passed'
