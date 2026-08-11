# Guest distro profiles

Status: experimental guest-userland portability
Authority: guest lifecycle and rootfs maintainers
Last reviewed: 2026-08-09

Debian remains Determination's only device-qualified guest. Arch Linux ARM and
Alpine are buildable profiles with explicit package, init, libc, and user-launch
adapters; neither may be described as graphics-qualified until the real
libhybris, hwcomposer, input handoff, audio, and restore gates pass on-device.

## Layout and switching

The proven Debian rootfs stays at `/data/determination/guest`. Optional rootfs
slots live below `/data/determination/guests/`, and
`/data/determination/active-guest` points to the selected rootfs. Each distro
keeps its own home directory. Share files through an explicit shared location;
do not reuse an entire home across different desktop package versions.

Switches are allowed only in phone mode. The manager stops LXC, changes the
active rootfs, regenerates configuration, starts the candidate, and runs a basic
boot health check. A failed candidate is rolled back to the prior guest.

```sh
det distro list
det distro status
det distro select debian|arch|alpine
```

## Build and install Arch Linux ARM

Import and independently verify Arch Linux ARM's official signing key
`68B3537F39A313B3E574D06777193F152BDBE6A6`. The builder refuses an unverified
rolling rootfs archive.

```sh
guest/build-portable-rootfs.sh arch
det distro install arch guest/determination-rootfs-arch.tar.gz
det distro select arch
det distro provision
```

The generic aarch64 rootfs is used because Android already supplies the running
kernel; no ALARM bootloader or kernel package participates in the LXC guest.

## Build and install Alpine

The Alpine builder is pinned to the official 3.24.0 aarch64 minirootfs SHA-256.
Override both `ALPINE_VERSION` and `ALPINE_SHA256` together when deliberately
updating that source.

```sh
guest/build-portable-rootfs.sh alpine
det distro install alpine guest/determination-rootfs-alpine.tar.gz
det distro select alpine
det distro provision
```

Alpine boots BusyBox init with OpenRC and uses musl. Determination does not add
glibc or `gcompat`; native guest components must build against the active libc.

## Graphics build gate

Portable archives include the pinned build entrypoints under
`/root/determination-build/`. After base provisioning and installation of the
separately built bionic `libhwc2_compat_layer.so`:

```sh
det guest-root /root/determination-build/build-libhybris.sh
det guest-root /root/determination-build/build-wlroots-phoc.sh
det guest-root /root/determination-build/setup-input.sh
```

Arch and Alpine build `libglibutil` and `libgbinder` from pinned sources instead
of borrowing Debian packages. The Android platform headers are extracted from a
pinned architecture-independent Droidian package with a fixed SHA-256. Alpine
skips Determination's glibc-only locale/TLS hook set; upstream libhybris' musl
path must pass `test_hwcomposer` before proceeding.

The honest acceptance sequence is:

1. Guest init, networking, package manager, unprivileged uid 1000, and SSH.
2. `test_hwcomposer` with the real Android 16 vendor stack.
3. Patched Phoc on the panel with EVIOCGRAB input.
4. Repeated phone-to-desktop-to-phone restoration.
5. Direct audio and concurrent external presenter qualification.

“The archive builds” proves only the build path. It does not prove a usable
desktop or make Arch/Alpine release-supported.

## Alpine qualification snapshot (2026-08-11)

On `guacamoleb`, Alpine 3.24 now passes archive validation and installation,
health-gated selection, cold boot, OpenRC service startup, uid-1000/group
mapping, gateway/internet/DNS, direct key-only SSH, shared device SSH identity,
seatd, and generated libinput udev data. Pinned `libglibutil` and `libgbinder`
also build and install natively against musl. The host returned to the proven
Debian slot after these tests.

Pinned upstream libhybris now builds and installs natively on musl without
glibc or `gcompat`. Its scoped source adapter covers the host-libc ABI gaps and
pins complete embedded-linker load groups when bionic Initial-Exec TLS makes
them non-unloadable. The property bridge survives 20 load/unload cycles, the
display-safe contract passes 20/20 (including the complete 2-fd + 22-int QTI
native handle), and `test_hwcomposer` rendered the expected diamond on the
1080x2340 panel through the real Android 16 vendor stack. SurfaceFlinger,
Android phone mode, guest networking, and the property bridge all recovered.

Alpine is still **not graphics-qualified**. This proves the libhybris and raw
HWC gate, not a usable desktop: patched Phoc with input, repeated desktop
restoration, direct audio playback, and external display remain untested.
`/etc/determination-ready` correctly keeps `graphics=unqualified`. Evidence:
`artifacts/alpine-libhybris-qualification-20260811.txt`.
