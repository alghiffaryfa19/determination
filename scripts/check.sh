#!/bin/sh
# Offline repo-wide verification sweep: syntax-checks every shell script,
# byte-compiles Python, validates JSON manifests. Runs shellcheck when
# installed. No device access, no builds, safe to run anytime.
set -u

cd "$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)"

fail=0; total=0
have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

# Vendor/generated trees that must never be swept.
# NOTE: must stay "-prune -o (tests) -print"; a bare trailing -prune makes
# the implicit-AND chain drop every non-pruned path.
prune='( -name .git -o -name toolchain -o -name __pycache__ -o -name libs -o -name obj -o -name build -o -name .gradle -o -name .kotlin -o -name dist -o -path ./kernel/src ) -prune'

echo "== shell syntax =="
# Extensionless executables with a #! shebang count as scripts too (det,
# toggle/desktop-on, guest/det-platform, ...).
for f in $(find . $prune -o \( -type f -name '*.sh' \) -print | sort); do
    total=$((total+1))
    if ! sh -n "$f" 2>/tmp/opencode/check.err && ! bash -n "$f" 2>>/tmp/opencode/check.err; then
        echo "FAIL sh/bash -n: $f"; cat /tmp/opencode/check.err; fail=$((fail+1))
    fi
done

for f in $(find . $prune -o \( -type f ! -name '*.*' \) -print | sort); do
    head -c 2 "$f" 2>/dev/null | grep -q '#!' || continue
    total=$((total+1))
    shebang=$(head -n 1 "$f")
    case $shebang in
        *python*)
            if ! python3 -m py_compile "$f" 2>/tmp/opencode/check.err; then
                echo "FAIL py_compile: $f"; cat /tmp/opencode/check.err; fail=$((fail+1))
            fi ;;
        *sh)
            if ! sh -n "$f" 2>/tmp/opencode/check.err; then
                echo "FAIL sh -n: $f"; cat /tmp/opencode/check.err; fail=$((fail+1))
            fi ;;
        *) ;; # other interpreters: nothing cheap to check offline
    esac
done
echo "checked $total shell scripts"

echo "== python =="
pys=0
for f in $(find . $prune -o \( -type f -name "*.py" \) -print  | sort); do
    pys=$((pys+1))
    if ! python3 -m py_compile "$f" 2>/tmp/opencode/check.err; then
        echo "FAIL py_compile: $f"; cat /tmp/opencode/check.err; fail=$((fail+1))
    fi
done
echo "checked $pys python files"

echo "== json =="
js=0
    for f in $(find . $prune -o \( -type f -name '*.json' \) -print | sort); do
    js=$((js+1))
    if ! python3 -m json.tool "$f" >/dev/null 2>/tmp/opencode/check.err; then
        echo "FAIL json: $f"; cat /tmp/opencode/check.err; fail=$((fail+1))
    fi
done
echo "checked $js json files"

if [ "$have_shellcheck" -eq 1 ]; then
    echo "== shellcheck =="
    sc_fail=0
    for f in $(find . $prune -o \( -type f \( -name '*.sh' -o -name 'det' \) \) -print | sort); do
        if ! shellcheck -S warning "$f" 2>/dev/null; then
            echo "WARN shellcheck: $f"; sc_fail=$((sc_fail+1))
        fi
    done
    echo "shellcheck flagged $sc_fail file(s)"
else
    echo "-- shellcheck not installed; skipping lint pass"
fi

rm -f /tmp/opencode/check.err
if [ "$fail" -eq 0 ]; then
    echo "check: OK"
else
    echo "check: $fail failure(s)" >&2
    exit 1
fi
