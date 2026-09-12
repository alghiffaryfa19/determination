#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)

out=$(env -i PATH=/usr/bin:/bin HOME=/home/aurora USER=aurora LOGNAME=aurora \
    "$ROOT/guest/aurora-phosh-session" --print-environment)
printf '%s\n' "$out" | grep -q '^XDG_CURRENT_DESKTOP=Phosh:GNOME$'
printf '%s\n' "$out" | grep -q '^GTK_USE_PORTAL=1$'
printf '%s\n' "$out" | grep -q '^EGL_PLATFORM=wayland$'
printf '%s\n' "$out" | grep -q '^GSK_RENDERER=ngl$'

grep -q '^PAMName=login$' "$ROOT/guest/aurora-phosh.service"
grep -q '^User=aurora$' "$ROOT/guest/aurora-phosh.service"
grep -q 'XDG_RUNTIME_DIR/bus' "$ROOT/guest/aurora-phosh-session"
grep -q 'systemctl --user mask --runtime --now' "$ROOT/guest/aurora-phosh-session"
grep -q 'DISABLE_RTKIT=1' "$ROOT/guest/aurora-audio-session"
grep -q "browser.content.full-zoom" "$ROOT/guest/aurora-firefox-content-defaults"
grep -q 'org.freedesktop.portal.Desktop' "$ROOT/guest/aurora-compat-check"
grep -q 'xdg-desktop-portal-phosh' "$ROOT/guest/setup-compatibility.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/.mozilla/firefox/test.default"
DB="$WORK/.mozilla/firefox/test.default/content-prefs.sqlite"
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript('''
CREATE TABLE groups (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE settings (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE prefs (
    id INTEGER PRIMARY KEY,
    groupID INTEGER,
    settingID INTEGER NOT NULL,
    value BLOB,
    timestamp INTEGER NOT NULL
);
''')
con.close()
PY
HOME="$WORK" "$ROOT/guest/aurora-firefox-content-defaults" >/dev/null
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
row = con.execute('''
SELECT prefs.value FROM prefs
JOIN settings ON prefs.settingID = settings.id
WHERE prefs.groupID IS NULL AND settings.name = 'browser.content.full-zoom'
''').fetchone()
assert row == (0.67,), row
con.execute('UPDATE prefs SET value = 0.8 WHERE groupID IS NULL')
con.commit()
con.close()
PY
HOME="$WORK" "$ROOT/guest/aurora-firefox-content-defaults" >/dev/null
python3 - "$DB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
assert con.execute('SELECT value FROM prefs WHERE groupID IS NULL').fetchone() == (0.8,)
con.close()
PY

echo 'compatibility contract tests passed'
