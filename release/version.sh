#!/bin/sh
# Shared version metadata loader/renderer for release packaging scripts.

aurora_load_version() {
    AURORA_VERSION_FILE=$1
    [ -f "$AURORA_VERSION_FILE" ] || {
        echo "missing version metadata: $AURORA_VERSION_FILE" >&2
        return 1
    }

    AURORA_VERSION=$(sed -n 's/^version=//p' "$AURORA_VERSION_FILE")
    AURORA_VERSION_CODE=$(sed -n 's/^versionCode=//p' "$AURORA_VERSION_FILE")
    AURORA_CODENAME=$(sed -n 's/^codename=//p' "$AURORA_VERSION_FILE")
    AURORA_RELEASE_STATUS=$(sed -n 's/^status=//p' "$AURORA_VERSION_FILE")

    printf '%s\n' "$AURORA_VERSION" | grep -Eq \
        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' || {
        echo "invalid SemVer in $AURORA_VERSION_FILE: $AURORA_VERSION" >&2
        return 1
    }
    case "$AURORA_VERSION_CODE" in
        ''|*[!0-9]*) echo "invalid versionCode in $AURORA_VERSION_FILE: $AURORA_VERSION_CODE" >&2; return 1 ;;
    esac
    [ "$AURORA_VERSION_CODE" -gt 0 ] && [ "$AURORA_VERSION_CODE" -le 2100000000 ] || {
        echo "versionCode must be between 1 and 2100000000: $AURORA_VERSION_CODE" >&2
        return 1
    }
    case "$AURORA_CODENAME" in
        ''|*[!A-Za-z0-9_-]*) echo "invalid codename in $AURORA_VERSION_FILE: $AURORA_CODENAME" >&2; return 1 ;;
    esac
    case "$AURORA_RELEASE_STATUS" in
        development|ready|released) ;;
        *) echo "invalid release status in $AURORA_VERSION_FILE: $AURORA_RELEASE_STATUS" >&2; return 1 ;;
    esac
}

aurora_render_version_template() {
    AURORA_TEMPLATE=$1
    AURORA_OUTPUT=$2
    sed -e "s/@VERSION@/$AURORA_VERSION/g" \
        -e "s/@VERSION_CODE@/$AURORA_VERSION_CODE/g" \
        -e "s/@CODENAME@/$AURORA_CODENAME/g" \
        "$AURORA_TEMPLATE" > "$AURORA_OUTPUT"
}
