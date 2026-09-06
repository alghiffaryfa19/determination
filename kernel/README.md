# Kernel builds

`build.sh` defaults to the proven OnePlus 7 (`guacamoleb`, 4.14) profile.
`fetch.sh` fetches that device's source, not a portable kernel.

## Redmi Note 13 Pro 5G (garnet)

Use the kernel source **revision and LLVM toolchain matching the installed ROM**.
First verify an unmodified ROM kernel rebuild boots. A matching version number
alone does not establish vendor module ABI compatibility.

Extract this phone's running config (requires Magisk Shell permission):

```sh
adb exec-out su -c 'cat /proc/config.gz' > artifacts/garnet-config.gz
gzip -dc artifacts/garnet-config.gz > artifacts/garnet-config.txt
```

With the ROM toolchain on `PATH`, run from the repository root:

```sh
DEVICE=garnet SRC=/absolute/path/to/kernel/xiaomi/sm7435 \
  BASECONFIG=/absolute/path/to/garnet-config.txt ./kernel/build.sh
./boot/repack.sh /absolute/path/to/matching-ROM-boot.img
```

Source/config/output paths supplied to `build.sh` are relative to `kernel/`
unless absolute. `OUT` defaults to `kernel/out`; with a custom `OUT`, pass the
printed kernel path explicitly as the second argument to `boot/repack.sh`.
Repack arguments are relative to `boot/` unless absolute.

The crDroid garnet `16.0` device tree specifies uncompressed `Image`, boot
header v4/GKI, and `TARGET_PRODUCT=garnet`. Its config recipe is
`gki_defconfig`, `vendor/parrot_GKI.config`, `vendor/garnet_GKI.config`, and
`vendor/debugfs.config`. Verify against your installed release, not merely the
latest branch. The running config is used here to preserve the installed
configuration before adding container options.

The base DTB is in `vendor_boot`; `dtbo` contains overlays. Do not concatenate
DTB onto the GKI kernel. Repack the matching original boot image to preserve
ramdisk and metadata; never flash a raw `Image` as a boot image.

This script builds the kernel only, not garnet's external vendor modules.
Modules in `vendor_boot` and `vendor_dlkm` must remain ABI-compatible; otherwise
use the ROM's full kernel/module build and packaging pipeline. Enabling pstore
also needs an appropriate reserved-memory/ramoops device-tree setup; config
options alone do not guarantee crash logs.

Keep original boot/vendor_boot/dtbo images and a tested recovery route before
any boot test. Fastboot `OKAY` confirms command completion, not successful boot.
Garnet is not device-qualified by these script changes.

## Other devices

Use `DEVICE=generic BASECONFIG=/absolute/path/to/device.config`, with matching
source and LLVM toolchain. This defaults to `Image`; `KERNEL_TARGET` accepts
`Image`, `Image.gz`, or `Image.gz-dtb`. Choose from the device's actual boot
layout, not kernel version alone. Non-OnePlus profiles do not force OnePlus
WLAN/USB drivers built-in.

Host regression tests: `python3 kernel/test-build.py`.
