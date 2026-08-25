#!/bin/sh
# Verify a release artifact directory against its SHA256SUMS.
# Usage: verify-artifacts.sh <artifact-dir> [SHA256SUMS-file]
set -eu
cd "$(CDPATH= cd -P "$(dirname "$0")" && pwd)"

dir=${1:-}
[ -d "$dir" ] || { echo "usage: $0 <artifact-dir> [SHA256SUMS]" >&2; exit 2; }
sums=${2:-"$dir/SHA256SUMS"}
[ -r "$sums" ] || { echo "no checksum file at $sums" >&2; exit 1; }

cd "$dir"
# Paths in SHA256SUMS are relative to the artifact dir; fail on any missing
# file so a truncated payload can never pass as verified.
missing=0
while read -r _ name; do
    [ -n "$name" ] || continue
    # sha256sum -c prints names like "artifacts/foo.zip"; strip leading ./
    name=${name#\./}
    [ -e "$name" ] || { echo "MISSING: $name" >&2; missing=$((missing+1)); }
done < "$sums"
[ "$missing" -eq 0 ] || exit 1

if sha256sum -c --quiet "$sums"; then
    echo "verified: $(grep -c . "$sums") artifact(s) match $sums"
else
    echo "CHECKSUM MISMATCH in $sums" >&2
    exit 1
fi
