#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/links"
export AURORA_OMARCHY_PATH="$ROOT/guest/omarchy"
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
"$AURORA_OMARCHY_PATH/bin/aurora-omarchy-compat" --install-links "$WORK/links"
# Mirror production precedence: bin/ first, compat links second.
export PATH="$WORK/links:$AURORA_OMARCHY_PATH/bin:$PATH"
grep -qx preserved "$WORK/links/omarchy-launch-terminal"
omarchy-launch-webapp 'https://example.org/path?a=1&b=2'
grep -Fxq 'https://example.org/path?a=1&b=2' "$TEST_LOG"
omarchy-pkg-present installed
! omarchy-pkg-present absent
omarchy-pkg-missing absent
! omarchy-pkg-missing installed
! omarchy-pkg-present --help
! omarchy-system-reboot
! omarchy-system-shutdown
! omarchy-update
! omarchy-brightness-display
! omarchy-brightness-display-ddc
! "$AURORA_OMARCHY_PATH/bin/aurora-omarchy-compat"
# uwsm-app shim passes the command through with or without the `--` separator.
[ "$(uwsm-app -- echo shimmed)" = shimmed ]
[ "$(uwsm-app echo shimmed)" = shimmed ]
# The floating-terminal launcher must not depend on the absent uwsm stack.
! grep -q uwsm "$AURORA_OMARCHY_PATH/bin/omarchy-launch-floating-terminal-with-presentation"
grep -q 'org.omarchy.terminal' "$AURORA_OMARCHY_PATH/bin/omarchy-launch-floating-terminal-with-presentation"
# Every upstream command name resolves: either a vendored file in bin/ or a
# Aurora-owned name served by the compat shim.
while IFS= read -r name; do
    case "$name" in
        compat-commands|aurora-omarchy-compat) continue ;;
    esac
    if [ ! -f "$AURORA_OMARCHY_PATH/bin/$name" ]; then
        [ -e "$WORK/links/$name" ] || { echo "unresolved: $name" >&2; exit 1; }
    fi
done < "$AURORA_OMARCHY_PATH/bin/compat-commands"
python3 - "$AURORA_OMARCHY_PATH" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
raw = (root / 'default/omarchy/omarchy-menu.jsonc').read_text()
stripped = re.sub(r'^\s*//[^\n]*', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
menu = json.loads(stripped)
assert menu['system.logout']['action'] == 'omarchy-system-logout'
assert menu['system.logout']['label'] == 'Return to Android'
assert not any(key in menu for key in ('system.reboot', 'system.shutdown', 'system.suspend', 'system.hibernate'))
for section in ('learn', 'trigger', 'style', 'setup', 'install', 'remove', 'update'):
    count = sum(1 for key in menu if key == section or key.startswith(section + '.'))
    assert count > 1, (section, count)
assert menu['learn.arch']['action'] == "omarchy-launch-webapp 'https://archlinuxarm.org'"
PY
echo 'Omarchy command tests passed'
