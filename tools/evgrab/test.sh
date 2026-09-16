#!/bin/sh
set -eu

BIN=$1
WORK=$2
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
INPUT="$WORK/evgrab-input"
EMPTY="$WORK/evgrab-empty"
SHIM="$WORK/evgrab-test-shim.so"
mkdir -p "$INPUT" "$EMPTY"
: > "$INPUT/event0"
: > "$INPUT/event1"

${CC:-cc} -std=c11 -fPIC -shared -Wall -Wextra -Werror \
    "$ROOT/tools/evgrab/evgrab-test-shim.c" -ldl -o "$SHIM"

LD_PRELOAD="$SHIM" "$BIN" -f -D "$INPUT" -a >"$WORK/evgrab.out" 2>&1 &
pid=$!
sleep 0.1
kill -0 "$pid"
grep -Fq "$INPUT/event0" "$WORK/evgrab.out"
grep -Fq "$INPUT/event1" "$WORK/evgrab.out"
kill -TERM "$pid"
wait "$pid"

if LD_PRELOAD="$SHIM" "$BIN" -f -D "$EMPTY" -a >"$WORK/evgrab-empty.out" 2>&1; then
    echo 'evgrab accepted an input directory with no event nodes' >&2
    exit 1
fi
grep -Fq 'nothing grabbed' "$WORK/evgrab-empty.out"

echo 'evgrab runtime behavior tests passed'
