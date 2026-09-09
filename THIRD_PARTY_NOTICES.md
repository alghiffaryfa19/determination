# Third-party notices

Determination's original source code is licensed under the [MIT License](LICENSE),
unless a file states otherwise. This notice records the direct third-party source
that Determination builds, vendors, modifies, links, or packages. It does not
replace the copyright notices carried by an installed Debian, Arch, or Alpine
rootfs.

## Release rule

Every release must include this file and the applicable verbatim licence texts
from [`LICENSES/`](LICENSES). A release which includes a component listed below
must also retain that component's copyright notices and provide its applicable
source, patches, and build instructions where its licence requires it.

The project's source pins are in [`guest/sources.lock`](guest/sources.lock) and
[`guest/fetch-dethyprland.sh`](guest/fetch-dethyprland.sh). A release must record
the exact kernel, minigbm, Mesa, and vendored-source revisions it actually used;
a branch name or moving clone is not sufficient provenance.

## Direct components

| Component | Licence | How Determination uses it | Release requirement |
| --- | --- | --- | --- |
| Linux kernel / crDroid SM8150 kernel | GPL-2.0-only, except files marked otherwise | Builds the custom kernel in the boot image. | Ship the exact corresponding source, configuration, Determination changes, and build recipe with every boot-image release. |
| LXC 4.0.12 | LGPL-2.1-or-later and GPL-2.0-only, by file | Builds and statically ships selected LXC host tools; [`guest/lxc-4.0.12-no-legacy-seccomp.patch`](guest/lxc-4.0.12-no-legacy-seccomp.patch) modifies an LGPL-2.1+ file. | Carry both licence texts, LXC notices, the exact source tarball/source reference, and the patch. |
| libhybris | Mixed file-level licences: Apache-2.0, BSD variants, GPL-3.0, ISC, LGPL-2.1, and MIT | Built from the pinned upstream source; the build recipe applies local compatibility changes. | Preserve all upstream licence files and publish the exact source revision plus all applied changes. Do not collapse it to one licence. |
| HWC2 compatibility layer and AOSP headers | libhybris's mixed file-level licences; AOSP source is predominantly Apache-2.0 | [`hwc2-compat/build.sh`](hwc2-compat/build.sh) builds bionic compatibility libraries from pinned libhybris compatibility code and Android 16 AOSP headers. | Preserve the source notices, record the AOSP tag and libhybris revision in the release manifest, and provide all local changes. Device `/system` libraries are linked from the user's own phone and must not be redistributed. |
| libdroid | BSD-3-Clause | Built from the pinned Droidian source. | Retain its copyright and BSD-3 notice. |
| wlroots | MIT | Built from the pinned Droidian fork for the Phoc path. | Retain the MIT notice. |
| Phoc / Phosh | GPL-3.0-or-later | The phone compositor and shell for the qualified Phosh session. | Distribute corresponding source and local modifications for any shipped modified build. |
| gmobile | LGPL-2.1-or-later, with GPL-3.0-or-later files | Optionally built by [`guest/setup-polish.sh`](guest/setup-polish.sh). | Preserve the upstream per-file notices and provide the applicable source when bundled. |
| libglibutil and libgbinder | BSD-3-Clause | Built from pinned source for non-Debian guest profiles. | Retain the BSD-3 notices. |
| minigbm | BSD-3-Clause | Built for the compositor-facing GBM layer; [`guest/build-minigbm.sh`](guest/build-minigbm.sh) changes its MSM driver-name check. | Retain the BSD-3 notice and publish the source revision and local change. |
| Mesa | Mixed, file-level licences | Optional native-Mesa/Turnip experiment; [`guest/build-mesa.sh`](guest/build-mesa.sh) applies a local Zink change. | Keep Mesa's full notice set and publish the selected source tag, source, and patch if its output is distributed. |
| KWin 6.3.6 | Mixed source tree; the modified KWin sources are GPL-2.0-or-later | Experimental Plasma Mobile backend. | The KWin patches are GPL-2.0-or-later. Retain the source package's complete notices and publish the corresponding modified source if shipped. |
| Hyprland, Aquamarine, Hypr utilities, Hypr protocols, and hyprwayland-scanner | BSD-3-Clause | Dethyprland sources fetched by [`guest/fetch-dethyprland.sh`](guest/fetch-dethyprland.sh); Determination patches live in [`graphics/dethyprland/patches/`](graphics/dethyprland/patches). | Retain BSD-3 notices for each upstream project and the local patch provenance. |
| Quickshell | LGPL-3.0-only, with upstream per-file exceptions | Vendored at [`guest/vendor/quickshell`](guest/vendor/quickshell) and modified by [`guest/quickshell-vendor-egl.patch`](guest/quickshell-vendor-egl.patch). | Preserve its `LICENSE`, `LICENSE-GPL`, and per-file notices; make the matching modified source available with each shipped binary. |
| wayland-protocols | MIT | Vendored at [`guest/vendor/wayland-protocols`](guest/vendor/wayland-protocols). | Preserve `COPYING` and the notices in individual protocol XML files. |
| Android Wayland EGL protocol | X11-style permissive licence | [`graphics/dethyprland/wayland-android.xml`](graphics/dethyprland/wayland-android.xml) is derived from Collabora's protocol. | Keep the copyright and permission notice embedded in that XML and in generated derivatives. |
| Virtual-pointer and virtual-keyboard protocol XML | MIT-style permissive licences embedded in each file | [`graphics/protocols/`](graphics/protocols/) is used by the input proxy. | Keep each XML's embedded copyright and permission notice in generated derivatives. |
| Magisk Zygisk API header | ISC | [`zygisk/jni/zygisk.hpp`](zygisk/jni/zygisk.hpp) is a copied API header. | Keep its existing ISC header. |
| AndroidX, Material Components, Jetpack Compose, Kotlin, and Haze | Apache-2.0 | Maven dependencies of the companion APK; versions are declared in [`companion/app/build.gradle.kts`](companion/app/build.gradle.kts). | Include their generated dependency notices in a distributed APK notice bundle. |

The Android platform libraries linked by the companion and the Android NDK build
tools are platform/toolchain dependencies. They are not copied into this source
tree; their notices must nevertheless be retained if a release redistributes
their code rather than relying on the device platform.

## Guest distribution packages

The guest profile chooses packages through `apt`, `pacman`, or `apk` at build
time. Those packages are not all source dependencies of this repository, but a
rootfs release is still a distribution of them. Keep the package manager's
copyright metadata in the rootfs and attach a package manifest for the exact
profile and repository snapshot used to build it. [`guest/setup-trim.sh`](guest/setup-trim.sh)
already preserves `/usr/share/doc/*/copyright`; do not remove those files from a
redistributed rootfs.

## Local patch licences

Each local patch starts with SPDX provenance stating its target upstream project
and licence. Those headers do not replace the target project's notices:

- Patches to BSD-3-Clause Hyprland/Aquamarine code are MIT-licensed additions
  distributed alongside the upstream BSD-3-Clause notices.
- KWin patches are GPL-2.0-or-later.
- The Quickshell patch is LGPL-3.0-only.
- The LXC `attach.c` patch is LGPL-2.1-or-later.
- `hwc2-compat/diag/direct_hwc2_fill_test.cpp` is Apache-2.0 because it is
  derived from libhybris's Apache-2.0 direct-HWC2 test; the remaining local
  HWC2 diagnostics are MIT unless marked otherwise.

## What this does not claim

This is a practical release inventory, not legal advice and not a complete SBOM.
Before publishing a boot image, rootfs, module ZIP, or APK, regenerate the
package/dependency manifest from the exact artifacts and confirm that every
shipped third-party binary has its required notice and source offer.
