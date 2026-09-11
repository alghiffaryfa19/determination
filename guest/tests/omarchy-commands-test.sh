#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/links"
export DET_OMARCHY_PATH="$ROOT/guest/omarchy"
export PATH="$WORK/bin:$PATH"
export TEST_LOG="$WORK/actions"
cat > "$WORK/bin/xdg-open" <<'MOCK'
#!/bin/sh
printf '%s\n' "$@" > "$TEST_LOG"
MOCK
cat > "$WORK/bin/pacman" <<'MOCK'
#!/bin/sh
[ "$1" = -Q ] && [ "$2" = installed ]
MOCK
chmod +x "$WORK/bin/xdg-open" "$WORK/bin/pacman"
printf 'preserved\n' > "$WORK/links/omarchy-launch-terminal"
"$DET_OMARCHY_PATH/bin/det-omarchy-compat" --install-links "$WORK/links"
export PATH="$WORK/links:$PATH"
grep -qx preserved "$WORK/links/omarchy-launch-terminal"
omarchy-launch-webapp 'https://example.org/path?a=1&b=2'
grep -Fxq 'https://example.org/path?a=1&b=2' "$TEST_LOG"
omarchy-pkg-present installed
! omarchy-pkg-present absent
omarchy-pkg-missing absent
! omarchy-pkg-missing installed
! omarchy-pkg-present --help
! omarchy-system-reboot
! omarchy-update
! "$DET_OMARCHY_PATH/bin/det-omarchy-compat"
python3 - "$DET_OMARCHY_PATH" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
menu = json.loads((root / 'default/omarchy/omarchy-menu.jsonc').read_text())
assert menu['system.logout']['action'] == 'omarchy-system-logout'
assert not any(key in menu for key in ('system.reboot', 'system.shutdown', 'system.suspend'))
PY
echo 'Omarchy command tests passed'
