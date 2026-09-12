# Install and recovery

Status: current safety guide
Authority: device qualification maintainers
Last reviewed: 2026-09-10

## PC installation workbench

Run `./aurora-installer` on a Linux PC. The terminal interview owns discovery,
release selection, automatic port builds, installation, and boot recovery.
The companion app has no system installer or boot writer.

Select one authorized device and inspect it. The next questions choose an
HTTPS release manifest or a local bundle, a distro, and a hostname. Prepare and
verify downloads every artifact, validates archive contents, saves a complete
boot backup on the PC, and repacks the release kernel around the device's own
Magisk ramdisk. It does not install userspace or write boot.

Install Aurora repeats validation, stages userspace, installs the module,
runtime, rootfs, and companion, and writes boot last. A failed write or readback
triggers a restore attempt from the verified backup. Reboot is a separate action.
Existing guest slots are retained rather than replaced.

Automatic port downloads a selected downstream source branch or uses a local
source folder. It merges the running config with Aurora requirements,
compiles the kernel, inserts the detected device profile into the shared module,
and assembles a local schema 2 bundle pinned to the connected Android build.
The interview offers to install that bundle when the build completes. New ports remain
experimental until hardware qualification; the build operation itself is real.

Recovery creates backups, restores a matching backup over rooted ADB, verifies
the running installation, and reboots. Operation logs remain on the PC. A bootloop still
requires the device's supported bootloader recovery procedure. The PC backup
includes the slot, exact Android fingerprint, serial, size, and SHA-256.

See the [workbench guide](../../installer/README.md) for prerequisites, supported
boot layouts, build inputs, and interruption behavior.

## Before an install or upgrade

The only supported target is listed in the [device reference](../reference/supported-device.md).
Back up data and retain a verified, target-slot-matched boot image outside the
source checkout. Confirm that the release manifest, compatibility check, and
checksums match the candidate artifacts.

Use a reversible validation path before writing a boot partition. A failed
build, an unknown device profile, or a missing recovery image is a stop
condition, not a reason to continue.

## Recovery baseline

Phone mode is the recovery baseline. The independent emergency restore path
must remain available when the guest, control daemon, or companion is absent.
Collect the relevant bounded logs and run the documented diagnostics before
retrying. Device-level flashing, partition writes, and recovery drills require
an explicit hardware qualification run; they are not host validation steps.

## Upgrade and rollback

Use only complete, versioned payloads with recorded hashes. Verify install,
upgrade, rollback, and restore against the exact supported ROM before a public
release. Keep one known-good payload and do not delete the external recovery
copy after a successful update.
