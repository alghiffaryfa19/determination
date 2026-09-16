#!/bin/sh
# Exercise host-runnable Aurora behavior. This is deliberately not a
# repository-hygiene check and it does not qualify a physical phone. Use
# tools/check-repo.sh for metadata/docs/static validation and tools/check-device.sh
# for a read-only acceptance pass against a live desktop session.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

python3 -m unittest discover -s installer/tests
sh recon/tests/test-classify.sh
sh toggle/tests/lifecycle-test.sh
sh toggle/tests/guest-distro-test.sh
sh toggle/tests/session-set-test.sh
sh toggle/tests/session-select-test.sh
sh toggle/tests/desktop-memory-test.sh
sh toggle/tests/guest-input-config-test.sh
sh guest/tests/audio-session-test.sh
sh guest/tests/compatibility-contract-test.sh
sh guest/tests/omarchy-commands-test.sh
sh guest/tests/omarchy-shell-test.sh
sh guest/tests/osk-test.sh
sh guest/tests/portable-rootfs-test.sh
sh guest/tests/platform-runtime-test.sh
python3 companion/branding/generate.py --check
sh guest/tests/hyprland-launch-test.sh
sh guest/tests/opal-runtime-test.sh
python3 guest/tests/hyprland-naming-test.py
python3 guest/tests/session-launch-test.py
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
sh tools/evgrab/test.sh "$WORK/evgrab-host" "$WORK"

echo "host behavioral checks passed"
echo "NOTE: this does not qualify a phone; run tools/check-device.sh for live acceptance"
