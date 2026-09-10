# Build and package

Status: current host-side guide
Authority: build and release maintainers
Last reviewed: 2026-08-09

## Scope

This guide identifies entrypoints. It does not authorize flashing or device
mutation. Read [install and recovery](install-and-recovery.md) before a device
qualification run.

## Host prerequisites

Use a Linux host with Git, Python 3, the Android SDK and NDK versions recorded
in the release manifest, official Android platform tools, and the component
toolchains described by their build scripts. Build inputs must be pinned for a
release; development branches are not release inputs.

## Entry points

| Component | Entry point | Output and gate |
|---|---|---|
| Recon | `recon/recon.sh --serial SERIAL` | reviewed report and capability classification |
| Kernel | `kernel/fetch.sh`, then `kernel/build.sh` | configuration and image candidate |
| Boot packaging | `boot/repack.sh` | validated boot-image candidate |
| Companion | Gradle wrapper in `companion/` | debug or signed release APK |
| Debian guest | `guest/build-rootfs.sh` | qualified baseline rootfs archive |
| Arch/Alpine guest | `guest/build-portable-rootfs.sh arch|alpine` | experimental profile archive; source verification required |
| Module and PC bundle | `magisk-module/build-module.sh`, `release/build-online-bundle.sh` | versioned archives and checksums |
| Online update bundle | `release/build-online-bundle.sh https://host/release/path` | app manifest, versioned artifacts, and checksums in `dist/online-release/` |
| Release audit | `release/check.sh check` | static development checks |

The companion defaults to the matching GitHub `releases/latest` manifest and
allows an HTTPS mirror in Settings. The online packager does not build or sign
anything. It refuses missing inputs, hashes the exact existing module, static
LXC runtime, guest rootfs, boot image, and signed APK, and emits the v2 schema
consumed by the app. Optional Arch and Alpine archives are included as
`experimental`; Debian is the qualified default.

Set `UPDATE_DEVICES` to a comma-separated list of Android product aliases and
`UPDATE_ANDROID_BUILDS` to the exact qualified Android build fingerprints.
The latter is mandatory: matching only `ro.product.device` is not enough to
authorize an unattended boot-partition write across ROM or OTA revisions.

```sh
UPDATE_DEVICES=guacamoleb,OnePlus7 \
UPDATE_ANDROID_BUILDS='oneplus/guacamoleb/...:16/BUILD/...' \
release/build-online-bundle.sh \
  "https://github.com/kriscrossapplesauce2004/determination/releases/download/v$VERSION"
```

The generated `determination-update.json`, every artifact, and `SHA256SUMS`
belong on the same GitHub release. The installer downloads over HTTPS, checks
the declared byte length and SHA-256, and then moves the verified file into a
root-only staging directory. A detached, pinned release-manifest signature is
still a ship requirement before this should be offered beyond trusted alpha
testers; HTTPS plus hashes in the same manifest does not defend against a
compromised release account.

Do not treat a successful build as a supported device result. Record the commit,
release manifest, profile digest, tool versions, and output hashes before any
hardware qualification.
