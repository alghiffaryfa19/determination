#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=${TMPDIR:-/tmp}/aurora-presenter-protocol-test
POOL_OUT=${TMPDIR:-/tmp}/aurora-gralloc-pool-protocol-test
${CC:-cc} -std=c11 -Wall -Wextra -Wpedantic -Werror \
    -I"$ROOT" "$ROOT/presenter-session.c" \
    "$ROOT/tests/presenter-protocol-test.c" -o "$OUT"
"$OUT"
${CC:-cc} -std=c11 -Wall -Wextra -Wpedantic -Werror \
    -I"$ROOT" "$ROOT/tests/gralloc-pool-protocol-test.c" -o "$POOL_OUT"
"$POOL_OUT"
rm -f "$OUT" "$POOL_OUT"
echo "presenter and gralloc-pool protocol policy tests passed"
