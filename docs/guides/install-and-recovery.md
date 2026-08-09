# Install and recovery

Status: current safety guide
Authority: device qualification maintainers
Last reviewed: 2026-08-09

## Guided rooted-device installer

For a published v2 online bundle, the main companion app can perform a fresh
install without ADB or a host PC:

1. Install the signed companion APK and grant its Magisk superuser request.
2. Open **Install**, check the official GitHub release, and review the detected
   device, active slot, Android fingerprint, battery, and free space.
3. Choose a published guest distro and the wired hostname/lifecycle options.
   Debian is qualified on `guacamoleb`; Arch and Alpine remain explicitly
   experimental until their complete hardware gates pass.
4. Tap **Install Determination** and keep Android in phone mode until it
   finishes. The transaction installs the module, static LXC runtime, selected
   rootfs and configuration before touching boot.
5. Reboot only when the app reports success.

The app never flashes the release boot image verbatim. It extracts only the
qualified kernel, repacks it around the phone's current Magisk-patched ramdisk,
backs up the complete active boot partition to `Download`, writes the active
slot, and verifies the flashed bytes. A readback mismatch triggers an immediate
restore attempt and must be treated as a recovery incident.

The app blocks a boot artifact unless both a device alias and the exact Android
build fingerprint match the release manifest. Unknown devices and post-OTA
builds are recon targets, not “try it and see” installer targets.

Enable **Settings → Advanced → Installer dry run** before the guided install to
exercise the complete non-destructive path. It downloads and hash-verifies all
selected artifacts, checks the module/runtime/rootfs layouts, rebuilds a boot
candidate around the current Magisk ramdisk, and creates and verifies the
recovery backup. It does not install the module, extract a guest, alter
configuration, or write the boot partition. Verified downloads, root staging
files, and the recovery backup are intentionally retained for the real run.

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
