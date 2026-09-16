#!/bin/sh
# Static/repository hygiene. These checks are useful, but passing them is not
# evidence that the convergence stack runs correctly on a device.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

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
python3 docs/check-links.py
python3 artifacts/build-index.py --check
python3 website/check-site.py
release/check.sh check

echo "repository hygiene checks passed"
