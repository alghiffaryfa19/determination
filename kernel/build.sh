#!/bin/sh
# Build against the installed ROM's source, config and toolchain.
set -eu
cd "$(dirname "$0")"

DEVICE="${DEVICE:-guacamoleb}"
SRC="${SRC:-$PWD/src}"
OUT="${OUT:-$PWD/out}"
JOBS="${JOBS:-$(nproc)}"
case "$SRC" in /*) ;; *) SRC="$PWD/$SRC" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
case "$DEVICE" in
    guacamoleb)
        BASECONFIG="${BASECONFIG:-../artifacts/kernel-config-full.txt}"
        KERNEL_TARGET="${KERNEL_TARGET:-Image.gz-dtb}"
        ;;
    garnet|generic)
        : "${BASECONFIG:?set BASECONFIG to this phone's extracted running config}"
        KERNEL_TARGET="${KERNEL_TARGET:-Image}"
        ;;
    *) echo "Unknown DEVICE: $DEVICE (use guacamoleb, garnet or generic)" >&2; exit 1 ;;
esac
case "$KERNEL_TARGET" in Image|Image.gz|Image.gz-dtb) ;; *) echo "Unsupported KERNEL_TARGET: $KERNEL_TARGET" >&2; exit 1 ;; esac
[ -d "$SRC" ] || { echo "Kernel source missing: $SRC" >&2; exit 1; }
[ -f "$BASECONFIG" ] || { echo "Base config missing: $BASECONFIG" >&2; exit 1; }
if [ "$DEVICE" = guacamoleb ]; then
    grep -Eq '^VERSION[[:space:]]*=[[:space:]]*4$' "$SRC/Makefile" &&
    grep -Eq '^PATCHLEVEL[[:space:]]*=[[:space:]]*14$' "$SRC/Makefile" || {
        echo "Default profile is OnePlus 7/4.14. Set DEVICE=garnet or generic and BASECONFIG for this phone." >&2
        exit 1
    }
    export PATH="$PWD/../toolchain/usr/bin:$PATH"
fi

kmake() {
    if [ "$DEVICE" = guacamoleb ]; then
        make -C "$SRC" O="$OUT" ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
            OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
            CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- "$@"
    else
        # Put the ROM's matching LLVM toolchain on PATH; do not substitute ours.
        make -C "$SRC" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 "$@"
    fi
}
if [ "$DEVICE" = garnet ]; then
    export TARGET_PRODUCT=garnet
fi
mkdir -p "$OUT"
rm -f "$OUT/kernel-image.path"
cp "$BASECONFIG" "$OUT/.config"
set -- "$PWD/determination.config"
if [ "$DEVICE" = guacamoleb ]; then
    set -- "$@" "$PWD/profiles/guacamoleb.config"
fi
(cd "$SRC" && KCONFIG_CONFIG="$OUT/.config" scripts/kconfig/merge_config.sh -O "$OUT" -m "$OUT/.config" "$@")
kmake olddefconfig

for opt in NAMESPACES USER_NS PID_NS IPC_NS NET_NS CGROUP_DEVICE CGROUP_PIDS POSIX_MQUEUE ANDROID_BINDERFS VETH OVERLAY_FS \
           VT VT_CONSOLE CHECKPOINT_RESTORE BINFMT_MISC NF_TABLES NFT_COMPAT IP6_NF_NAT MACVLAN VLAN_8021Q \
           PSTORE PSTORE_RAM PSTORE_PMSG; do
    grep -q "^CONFIG_$opt=y" "$OUT/.config" || { echo "MERGE FAILED: CONFIG_$opt not set" >&2; exit 1; }
done
if [ "$DEVICE" = guacamoleb ]; then
    grep -q '^CONFIG_QCA_CLD_WLAN=y' "$OUT/.config" || { echo 'MERGE FAILED: CONFIG_QCA_CLD_WLAN not set' >&2; exit 1; }
fi
! grep -q '^CONFIG_FRAMEBUFFER_CONSOLE=y' "$OUT/.config" || { echo 'MERGE FAILED: fbcon enabled; would fight SF for the panel' >&2; exit 1; }
echo 'config OK: all Determination options present'
kmake -j"$JOBS" "$KERNEL_TARGET"
IMAGE="$OUT/arch/arm64/boot/$KERNEL_TARGET"
[ -s "$IMAGE" ] || { echo "Build produced no kernel: $IMAGE" >&2; exit 1; }
printf '%s\n' "$IMAGE" > "$OUT/kernel-image.path"
printf '\nKernel: %s\nNext: boot/repack.sh <matching-ROM-boot.img> "%s"\n' "$IMAGE" "$IMAGE"
if [ "$DEVICE" != guacamoleb ]; then
    echo 'Kernel-only build: vendor_boot/vendor_dlkm modules must remain ABI-compatible.'
    echo 'Keep matching DTB/DTBO and boot metadata; do not append DTB to a GKI Image.'
fi
