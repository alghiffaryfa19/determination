#!/bin/sh
# Stage a complete PC installer release with versioned update metadata.
# Upload every file in dist/online-release/ to the release URL passed here.

set -eu
cd "$(dirname "$0")/.."

. release/version.sh
det_load_version version.properties

BASE_URL=${1:-}
case "$BASE_URL" in
    https://*) BASE_URL=${BASE_URL%/} ;;
    *) echo "usage: $0 https://artifact-host/path" >&2; exit 2 ;;
esac

OUT=${ONLINE_RELEASE_OUT:-dist/online-release}
MODULE=${RELEASE_MODULE:-magisk-module/determination-magisk-v$DET_VERSION.zip}
BOOT=${RELEASE_BOOT:-boot/determination-boot.img}
APK=${RELEASE_APK:-companion/app/build/outputs/apk/release/app-release.apk}
LXC_DIR=${RELEASE_LXC_DIR:-dist/lxc-bin}
DEBIAN_ROOTFS=${DEBIAN_ROOTFS:-guest/rootfs.tar.gz}
PORTABLE_ROOTFS_DIR=${PORTABLE_ROOTFS_DIR:-guest}

for artifact in "$MODULE" "$BOOT" "$APK" "$DEBIAN_ROOTFS"; do
    [ -f "$artifact" ] || { echo "missing release artifact: $artifact" >&2; exit 1; }
done
for tool in lxc-start lxc-stop lxc-attach lxc-info lxc-ls lxc-console lxc-execute; do
    [ -f "$LXC_DIR/$tool" ] || { echo "missing static LXC runtime: $LXC_DIR/$tool" >&2; exit 1; }
done

DEVICES=${UPDATE_DEVICES:-guacamoleb,OnePlus7}
case "$DEVICES" in
    ''|*[!A-Za-z0-9._,-]*) echo "invalid UPDATE_DEVICES: $DEVICES" >&2; exit 2 ;;
esac
ANDROID_BUILDS=${UPDATE_ANDROID_BUILDS:-}
case "$ANDROID_BUILDS" in
    '') echo "UPDATE_ANDROID_BUILDS must list exact qualified Android build fingerprints" >&2; exit 2 ;;
    *[!A-Za-z0-9._,:/-]*) echo "invalid UPDATE_ANDROID_BUILDS" >&2; exit 2 ;;
esac

json_array() {
    old_ifs=$IFS
    IFS=,
    set -- $1
    IFS=$old_ifs
    result='['
    separator=
    for value in "$@"; do
        result="$result$separator\"$value\""
        separator=,
    done
    printf '%s]' "$result"
}

rm -rf "$OUT"
mkdir -p "$OUT"
MODULE_NAME="determination-magisk-v$DET_VERSION.zip"
BOOT_NAME="determination-boot-v$DET_VERSION.img"
APK_NAME="determination-companion-v$DET_VERSION.apk"
RUNTIME_NAME="determination-runtime-aarch64-v$DET_VERSION.tar.gz"
DEBIAN_NAME="determination-rootfs-debian-v$DET_VERSION.tar.gz"
cp "$MODULE" "$OUT/$MODULE_NAME"
cp "$BOOT" "$OUT/$BOOT_NAME"
cp "$APK" "$OUT/$APK_NAME"
(cd "$LXC_DIR" && tar --sort=name --mtime="@${SOURCE_DATE_EPOCH:-315532800}" \
    --owner=0 --group=0 --numeric-owner \
    -cf - lxc-start lxc-stop lxc-attach lxc-info lxc-ls lxc-console lxc-execute) \
    | gzip -n -9 > "$OUT/$RUNTIME_NAME"
cp "$DEBIAN_ROOTFS" "$OUT/$DEBIAN_NAME"

MODULE_SHA=$(sha256sum "$OUT/$MODULE_NAME" | cut -d' ' -f1)
BOOT_SHA=$(sha256sum "$OUT/$BOOT_NAME" | cut -d' ' -f1)
APK_SHA=$(sha256sum "$OUT/$APK_NAME" | cut -d' ' -f1)
RUNTIME_SHA=$(sha256sum "$OUT/$RUNTIME_NAME" | cut -d' ' -f1)
DEBIAN_SHA=$(sha256sum "$OUT/$DEBIAN_NAME" | cut -d' ' -f1)
MODULE_SIZE=$(stat -c%s "$OUT/$MODULE_NAME")
BOOT_SIZE=$(stat -c%s "$OUT/$BOOT_NAME")
APK_SIZE=$(stat -c%s "$OUT/$APK_NAME")
RUNTIME_SIZE=$(stat -c%s "$OUT/$RUNTIME_NAME")
DEBIAN_SIZE=$(stat -c%s "$OUT/$DEBIAN_NAME")
DEVICE_JSON=$(json_array "$DEVICES")
ANDROID_BUILD_JSON=$(json_array "$ANDROID_BUILDS")
PUBLISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
    printf '{\n'
    printf '  "schema": 2,\n'
    printf '  "version": "%s",\n' "$DET_VERSION"
    printf '  "versionCode": %s,\n' "$DET_VERSION_CODE"
    printf '  "codename": "%s",\n' "$DET_CODENAME"
    printf '  "channel": "%s",\n' "$DET_RELEASE_STATUS"
    printf '  "publishedAt": "%s",\n' "$PUBLISHED_AT"
    printf '  "artifacts": [\n'
    printf '    {"type":"module","name":"%s","url":"%s/%s","sha256":"%s","size":%s,"devices":%s,"support":"qualified","description":"Root integration and on-device control plane"},\n' \
        "$MODULE_NAME" "$BASE_URL" "$MODULE_NAME" "$MODULE_SHA" "$MODULE_SIZE" "$DEVICE_JSON"
    printf '    {"type":"runtime","name":"%s","url":"%s/%s","sha256":"%s","size":%s,"devices":%s,"abis":["arm64-v8a"],"support":"qualified","description":"Static Android-host LXC runtime"},\n' \
        "$RUNTIME_NAME" "$BASE_URL" "$RUNTIME_NAME" "$RUNTIME_SHA" "$RUNTIME_SIZE" "$DEVICE_JSON"
    printf '    {"type":"rootfs","name":"%s","url":"%s/%s","sha256":"%s","size":%s,"abis":["arm64-v8a"],"distro":"debian","support":"qualified","description":"Device-qualified Debian and Phosh desktop"},\n' \
        "$DEBIAN_NAME" "$BASE_URL" "$DEBIAN_NAME" "$DEBIAN_SHA" "$DEBIAN_SIZE"
    for profile in arch alpine; do
        rootfs="$PORTABLE_ROOTFS_DIR/determination-rootfs-$profile.tar.gz"
        [ -f "$rootfs" ] || continue
        rootfs_name="determination-rootfs-$profile-v$DET_VERSION.tar.gz"
        cp "$rootfs" "$OUT/$rootfs_name"
        rootfs_sha=$(sha256sum "$OUT/$rootfs_name" | cut -d' ' -f1)
        rootfs_size=$(stat -c%s "$OUT/$rootfs_name")
        pretty=$(case "$profile" in arch) echo 'Arch Linux ARM';; alpine) echo 'Alpine Linux';; esac)
        printf '    {"type":"rootfs","name":"%s","url":"%s/%s","sha256":"%s","size":%s,"abis":["arm64-v8a"],"distro":"%s","support":"experimental","description":"%s base; graphics qualification still required"},\n' \
            "$rootfs_name" "$BASE_URL" "$rootfs_name" "$rootfs_sha" "$rootfs_size" "$profile" "$pretty"
    done
    printf '    {"type":"boot","name":"%s","url":"%s/%s","sha256":"%s","size":%s,"devices":%s,"androidBuilds":%s,"support":"qualified","description":"Device kernel; installer preserves the current Magisk ramdisk"},\n' \
        "$BOOT_NAME" "$BASE_URL" "$BOOT_NAME" "$BOOT_SHA" "$BOOT_SIZE" "$DEVICE_JSON" "$ANDROID_BUILD_JSON"
    printf '    {"type":"companion","name":"%s","url":"%s/%s","sha256":"%s","size":%s,"abis":["arm64-v8a","armeabi-v7a"],"support":"qualified","description":"Determination companion controller"}\n' \
        "$APK_NAME" "$BASE_URL" "$APK_NAME" "$APK_SHA" "$APK_SIZE"
    printf '  ]\n}\n'
} > "$OUT/determination-update.json"

(cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
printf 'Online release bundle: %s\n' "$OUT"
printf 'Manifest URL: %s/determination-update.json\n' "$BASE_URL"
