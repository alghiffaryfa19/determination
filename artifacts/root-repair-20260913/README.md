# Magisk kernel-patch recovery

The installed kernel retained `skip_initramfs\0`, while the verified pre-install
backup contained Magisk's `want_initramfs\0` patch. Both images contained an
identical Magisk ramdisk. After reboot, Android started but `su` was absent.

The installer now carries the legacy SAR patch from the original kernel to its
replacement before hashing, repacking, and unpacking the result for verification.
Missing replacement markers fail the build. Tests cover raw kernel and release
image inputs, unchanged ramdisk contents, idempotence, and missing markers.

Original backup:
`/home/melissa/.local/share/aurora/backups/20260913-222251-3c379dda/boot.img`
SHA-256: `6602f72346e3ba906abfb4c87b1bf3ab17e518a929d0cfdc31b1312b6c16109f`

Corrected image:
`build/01e18b3fb78b4eb5b4b684a1f5438934/aurora-boot.img`
SHA-256: `06dbe9c8223107ac9e62fbc7fd5c75b8ec03b38de9a0a1ee2389005c269a3bee`

Device boot verification is pending. The first temporary boot attempt did not
transfer the image: the phone returned from fastboot to Android beforehand.
