#!/bin/sh
# Run every host-safe Aurora validation from one entrypoint.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git ls-files -co --exclude-standard | while IFS= read -r file; do
    [ -f "$file" ] || continue
    magic=$(dd if="$file" bs=2 count=1 2>/dev/null || true)
    [ "$magic" = '#!' ] || continue
    shebang=$(sed -n '1p' "$file" 2>/dev/null || true)
    case "$shebang" in
        '#!'*'/bash'*) bash -n "$file" ;;
        '#!'*'/sh'*) sh -n "$file" ;;
    esac
done

python3 -m py_compile \
    recon/classify.py docs/check-links.py artifacts/build-index.py \
    website/check-site.py website/optimize-images.py
python3 -m unittest discover -s installer/tests
sh recon/tests/test-classify.sh
sh toggle/tests/lifecycle-test.sh
sh toggle/tests/guest-distro-test.sh
sh toggle/tests/session-set-test.sh
sh toggle/tests/session-select-test.sh
sh guest/tests/audio-session-test.sh
sh guest/tests/compatibility-contract-test.sh
sh guest/tests/omarchy-commands-test.sh
sh guest/tests/portable-rootfs-test.sh
python3 docs/check-links.py
python3 artifacts/build-index.py --check
python3 website/check-site.py
release/check.sh check
sh graphics/test.sh

if command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    sh control/build.sh host
    sh audio/build.sh host
else
    CXX=${CXX:-g++}
    "$CXX" -std=c++20 -O2 -Wall -Wextra -Wpedantic -Werror \
        -Icontrol/include \
        control/src/adapter.cpp control/src/journal.cpp control/src/observability.cpp \
        control/src/policy.cpp control/src/protocol.cpp control/src/state.cpp \
        control/src/system.cpp control/src/transition.cpp \
        control/tests/control_tests.cpp -o "$WORK/control-tests"
    "$WORK/control-tests"

    "$CXX" -std=c++20 -O2 -Wall -Wextra -Wpedantic -Werror \
        -ffunction-sections -fdata-sections audio/src/aurora_audio_probe.cpp \
        -Wl,--gc-sections -o "$WORK/aurora-audio-probe"
    "$CXX" -std=c++20 -O2 -Wall -Wextra -Wpedantic -Werror \
        -ffunction-sections -fdata-sections audio/src/aurora_audio_owner.cpp \
        -Wl,--gc-sections -o "$WORK/aurora-audio-owner"
    sh audio/tests/fixture-test.sh "$WORK/aurora-audio-probe"
    sh audio/tests/owner-fixture-test.sh \
        "$WORK/aurora-audio-owner" "$WORK/aurora-audio-probe"
fi

${CC:-cc} -D_GNU_SOURCE -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
    tools/evgrab/evgrab.c -o "$WORK/evgrab-host"

echo "all host-safe checks passed"
