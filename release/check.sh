#!/bin/sh
# Audit central version metadata and, in `ship` mode, enforce the minimum
# conditions for tagging a project release. This does not publish anything.

set -eu
cd "$(dirname "$0")/.."

AURORA_MODE=${1:-check}
case "$AURORA_MODE" in
    check|ship) ;;
    *) echo "usage: release/check.sh [check|ship]" >&2; exit 2 ;;
esac

. release/version.sh
aurora_load_version version.properties

AURORA_FAILURES=0
AURORA_CHECK_TMP=$(mktemp -d)
trap 'rm -rf "$AURORA_CHECK_TMP"' EXIT

ok()   { printf 'ok:   %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; AURORA_FAILURES=$((AURORA_FAILURES + 1)); }

check_equal() {
    AURORA_LABEL=$1 AURORA_WANT=$2 AURORA_GOT=$3
    if [ "$AURORA_WANT" = "$AURORA_GOT" ]; then
        ok "$AURORA_LABEL = $AURORA_GOT"
    else
        fail "$AURORA_LABEL: wanted '$AURORA_WANT', got '$AURORA_GOT'"
    fi
}

ok "project version: $AURORA_VERSION"
ok "release train: $AURORA_CODENAME"
ok "versionCode: $AURORA_VERSION_CODE"
ok "status: $AURORA_RELEASE_STATUS"

AURORA_RELEASE_BASE=${AURORA_VERSION%%-*}
AURORA_MANIFEST="release/manifests/v$AURORA_VERSION.manifest"

[ "$AURORA_VERSION_CODE" -gt 11 ] \
    && ok "versionCode is above every legacy component code" \
    || fail "versionCode must remain above the legacy maximum of 11"

AURORA_TEMPLATE_INDEX=0
check_template() {
    AURORA_TEMPLATE_INDEX=$((AURORA_TEMPLATE_INDEX + 1))
    AURORA_TEMPLATE_PATH=$1
    AURORA_RENDERED="$AURORA_CHECK_TMP/$AURORA_TEMPLATE_INDEX-module.prop"
    aurora_render_version_template "$AURORA_TEMPLATE_PATH" "$AURORA_RENDERED"
    AURORA_RENDERED_VERSION=$(sed -n 's/^version=//p' "$AURORA_RENDERED")
    AURORA_RENDERED_CODE=$(sed -n 's/^versionCode=//p' "$AURORA_RENDERED")
    check_equal "$AURORA_TEMPLATE_PATH version" "v$AURORA_VERSION" "$AURORA_RENDERED_VERSION"
    check_equal "$AURORA_TEMPLATE_PATH versionCode" "$AURORA_VERSION_CODE" "$AURORA_RENDERED_CODE"
    grep -Fq "$AURORA_CODENAME" "$AURORA_RENDERED" \
        && ok "$AURORA_TEMPLATE_PATH contains $AURORA_CODENAME" \
        || fail "$AURORA_TEMPLATE_PATH does not expose $AURORA_CODENAME"
}

check_template magisk-module/module.prop.in

grep -Fq 'rootProject.file("../version.properties")' companion/app/build.gradle.kts \
    && grep -Fq 'versionCode = auroraVersionCode' companion/app/build.gradle.kts \
    && grep -Fq 'versionName = auroraVersionName' companion/app/build.gradle.kts \
    && ok "companion consumes central version metadata" \
    || fail "companion does not consume central version metadata"

for AURORA_PACKAGER in \
    magisk-module/build-module.sh \
    release/build-online-bundle.sh
do
    grep -Fq 'aurora_load_version' "$AURORA_PACKAGER" \
        && ok "$AURORA_PACKAGER consumes central version metadata" \
        || fail "$AURORA_PACKAGER does not consume central version metadata"
done

python3 -m json.tool release/update-manifest.schema.json >/dev/null \
    && grep -Fq '"runtime"' release/update-manifest.schema.json \
    && grep -Fq '"rootfs"' release/update-manifest.schema.json \
    && grep -Fq '"androidBuilds"' release/update-manifest.schema.json \
    && ok "online installer schema covers runtime, rootfs, and exact Android builds" \
    || fail "online installer schema is invalid or incomplete"

grep -Fq "$AURORA_RELEASE_BASE \"$AURORA_CODENAME\"" CHANGELOG.md \
    && ok "changelog entry exists" \
    || fail "missing changelog entry for $AURORA_RELEASE_BASE \"$AURORA_CODENAME\""
grep -Fq "## $AURORA_CODENAME: $AURORA_RELEASE_BASE" RELEASES.md \
    && ok "release plan contains $AURORA_RELEASE_BASE $AURORA_CODENAME" \
    || fail "release plan does not contain $AURORA_RELEASE_BASE $AURORA_CODENAME"

validate_manifest() {
    AURORA_MANIFEST_FILE=$1
    [ -f "$AURORA_MANIFEST_FILE" ] || { fail "missing release manifest: $AURORA_MANIFEST_FILE"; return; }
    if ! awk '
        /^[[:space:]]*(#|$)/ { next }
        !/^[A-Za-z0-9][A-Za-z0-9._-]*=/ { print "invalid line " NR; bad=1; next }
        { key=$0; sub(/=.*/, "", key); if (seen[key]++) { print "duplicate key " key; bad=1 } }
        END { exit bad }
    ' "$AURORA_MANIFEST_FILE" >"$AURORA_CHECK_TMP/manifest-errors"; then
        while IFS= read -r AURORA_ERROR; do fail "$AURORA_MANIFEST_FILE: $AURORA_ERROR"; done <"$AURORA_CHECK_TMP/manifest-errors"
        return
    fi
    for AURORA_REQUIRED in schema project.commit device.product device.rom \
        input.boot.pristine.sha256 input.kernel.config.sha256 \
        toolchain.android.ndk toolchain.gradle source.libhybris.url \
        source.libhybris.revision source.wlroots.url source.wlroots.revision \
        source.phoc.url source.phoc.revision source.mesa.revision \
        source.minigbm.revision source.lxc.revision input.hwc.google_archive.sha256 \
        input.companion.dependencies.sha256 input.guest.base.sha256 \
        input.local.patches.sha256 signing.companion.certificate.sha256
    do
        AURORA_VALUE=$(sed -n "s/^$AURORA_REQUIRED=//p" "$AURORA_MANIFEST_FILE")
        [ -n "$AURORA_VALUE" ] || { fail "$AURORA_MANIFEST_FILE: missing $AURORA_REQUIRED"; continue; }
        case "$AURORA_REQUIRED" in
            *.revision|project.commit)
                case "$AURORA_VALUE" in
                    UNRESOLVED) ;;
                    *) printf '%s' "$AURORA_VALUE" | grep -Eq '^[0-9a-f]{40}$' \
                        || fail "$AURORA_MANIFEST_FILE: $AURORA_REQUIRED is not a Git object ID" ;;
                esac ;;
            *.sha256)
                case "$AURORA_VALUE" in
                    UNRESOLVED) ;;
                    *) printf '%s' "$AURORA_VALUE" | grep -Eq '^[0-9a-f]{64}$' \
                        || fail "$AURORA_MANIFEST_FILE: $AURORA_REQUIRED is not a SHA-256 digest" ;;
                esac ;;
        esac
        if [ "$AURORA_VALUE" = UNRESOLVED ]; then
            if [ "$AURORA_MODE" = ship ]; then fail "$AURORA_MANIFEST_FILE: unresolved $AURORA_REQUIRED"
            else warn "$AURORA_MANIFEST_FILE: unresolved $AURORA_REQUIRED"; fi
        fi
    done
    ok "release manifest syntax: $AURORA_MANIFEST_FILE"
}

validate_manifest "$AURORA_MANIFEST"

manifest_value() { sed -n "s/^$1=//p" "$AURORA_MANIFEST"; }

validate_source_locks() {
    [ -f guest/sources.lock ] || { fail "missing guest/sources.lock"; return; }
    # shellcheck disable=SC1091
    . guest/sources.lock
    check_equal "guest libhybris pin" "$(manifest_value source.libhybris.revision)" "$LIBHYBRIS_COMMIT"
    check_equal "guest wlroots pin" "$(manifest_value source.wlroots.revision)" "$WLROOTS_COMMIT"
    check_equal "guest phoc pin" "$(manifest_value source.phoc.revision)" "$PHOC_COMMIT"
    AURORA_HWC_LIBHYBRIS=$(sed -n 's/^LIBHYBRIS_REV=//p' hwc2-compat/build.sh | head -n 1)
    [ -n "$AURORA_HWC_LIBHYBRIS" ] \
        && check_equal "HWC libhybris pin" "$LIBHYBRIS_COMMIT" "$AURORA_HWC_LIBHYBRIS" \
        || fail "HWC build does not declare a libhybris revision"
}

validate_source_locks

AURORA_HEAD=$(git rev-parse --short=12 HEAD)
if [ -n "$(git status --porcelain)" ]; then
    if [ "$AURORA_MODE" = ship ]; then fail "worktree is dirty at $AURORA_HEAD"
    else warn "worktree is dirty at $AURORA_HEAD (expected during development)"; fi
else
    ok "worktree is clean at $AURORA_HEAD"
fi

if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    AURORA_UPSTREAM=$(git rev-parse --abbrev-ref '@{upstream}')
    set -- $(git rev-list --left-right --count HEAD..."$AURORA_UPSTREAM")
    AURORA_AHEAD=$1 AURORA_BEHIND=$2
    if [ "$AURORA_BEHIND" -gt 0 ]; then
        if [ "$AURORA_MODE" = ship ]; then
            fail "HEAD is $AURORA_AHEAD ahead / $AURORA_BEHIND behind $AURORA_UPSTREAM"
        else
            warn "HEAD is $AURORA_AHEAD ahead / $AURORA_BEHIND behind $AURORA_UPSTREAM"
        fi
    else
        ok "HEAD contains $AURORA_UPSTREAM ($AURORA_AHEAD local commits)"
    fi
else
    warn "branch has no upstream; remote ancestry was not checked"
fi

ok "release-critical guest and HWC sources are validated against immutable pins"

AURORA_MODULE_ZIP="magisk-module/aurora-magisk-v$AURORA_VERSION.zip"
if [ -f "$AURORA_MODULE_ZIP" ]; then
    AURORA_ZIP_VERSION=$(python3 -c "import zipfile; p=zipfile.ZipFile('$AURORA_MODULE_ZIP').read('module.prop').decode(); print(next(x[8:] for x in p.splitlines() if x.startswith('version=')))")
    AURORA_ZIP_CODE=$(python3 -c "import zipfile; p=zipfile.ZipFile('$AURORA_MODULE_ZIP').read('module.prop').decode(); print(next(x[12:] for x in p.splitlines() if x.startswith('versionCode=')))")
    check_equal "built Magisk module version" "v$AURORA_VERSION" "$AURORA_ZIP_VERSION"
    check_equal "built Magisk module versionCode" "$AURORA_VERSION_CODE" "$AURORA_ZIP_CODE"
else
    warn "current Magisk module has not been built"
fi

if [ -f companion/app/build/outputs/apk/release/app-release-unsigned.apk ] \
    && [ ! -f companion/app/build/outputs/apk/release/app-release.apk ]; then
    warn "companion release compiles but is unsigned; configure the Aqua signing identity before shipping"
fi

if [ "$AURORA_MODE" = ship ]; then
    [ "$AURORA_RELEASE_STATUS" = ready ] \
        && ok "release status is ready" \
        || fail "release status is '$AURORA_RELEASE_STATUS', not 'ready'"

    AURORA_TAG="v$AURORA_VERSION"
    if git rev-parse -q --verify "refs/tags/$AURORA_TAG" >/dev/null; then
        AURORA_TAG_HEAD=$(git rev-list -n1 "$AURORA_TAG")
        AURORA_FULL_HEAD=$(git rev-parse HEAD)
        [ "$AURORA_TAG_HEAD" = "$AURORA_FULL_HEAD" ] \
            && ok "$AURORA_TAG points at HEAD" \
            || fail "$AURORA_TAG already exists on another commit"
    else
        ok "$AURORA_TAG is available"
    fi

    for AURORA_ARTIFACT in \
        boot/aurora-boot.img \
        "$AURORA_MODULE_ZIP" \
        companion/app/build/outputs/apk/release/app-release.apk \
        dist/usb-payload/SHA256SUMS \
        dist/online-release/aurora-update.json \
        dist/online-release/SHA256SUMS \
        "$AURORA_MANIFEST"
    do
        [ -f "$AURORA_ARTIFACT" ] \
            && ok "artifact exists: $AURORA_ARTIFACT" \
            || fail "missing release artifact: $AURORA_ARTIFACT"
    done

    if [ -f dist/usb-payload/SHA256SUMS ]; then
        (cd dist/usb-payload && sha256sum -c SHA256SUMS) \
            && ok "USB payload checksums verify" \
            || fail "USB payload checksums do not verify"
        for AURORA_PAYLOAD_FILE in \
            "aurora-magisk-v$AURORA_VERSION.zip" \
            "aurora-companion-v$AURORA_VERSION.apk"
        do
            grep -Fq "$AURORA_PAYLOAD_FILE" dist/usb-payload/SHA256SUMS \
                && ok "USB payload contains $AURORA_PAYLOAD_FILE" \
                || fail "USB payload checksums do not reference $AURORA_PAYLOAD_FILE"
        done
    fi

    if [ -f dist/online-release/SHA256SUMS ]; then
        (cd dist/online-release && sha256sum -c SHA256SUMS) \
            && ok "online installer checksums verify" \
            || fail "online installer checksums do not verify"
    fi
    if [ -f dist/online-release/aurora-update.json ]; then
        python3 -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
types = {a.get("type") for a in p.get("artifacts", [])}
boots = [a for a in p.get("artifacts", []) if a.get("type") == "boot"]
debian = [a for a in p.get("artifacts", []) if a.get("type") == "rootfs" and a.get("distro") == "debian" and a.get("support") == "qualified"]
assert p.get("schema") == 2
assert {"module", "runtime", "rootfs", "boot", "companion"} <= types
assert boots and all(a.get("devices") and a.get("androidBuilds") for a in boots)
assert debian
' dist/online-release/aurora-update.json \
            && ok "online bundle is a complete exact-build installer" \
            || fail "online bundle is update-only, unsafe, or malformed"
    fi

    if [ -f companion/app/build/outputs/apk/release/app-release.apk ]; then
        if command -v apksigner >/dev/null 2>&1; then
            apksigner verify --verbose --print-certs \
                companion/app/build/outputs/apk/release/app-release.apk >/dev/null \
                && ok "companion APK signature verifies" \
                || fail "companion APK signature does not verify"
        else
            fail "apksigner is required to verify the companion release APK"
        fi
    fi
fi

if [ "$AURORA_FAILURES" -ne 0 ]; then
    printf '\n%d release check(s) failed.\n' "$AURORA_FAILURES" >&2
    exit 1
fi

printf '\nAurora %s "%s": %s checks passed.\n' \
    "$AURORA_VERSION" "$AURORA_CODENAME" "$AURORA_MODE"
