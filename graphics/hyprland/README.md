# Hyprland bring-up

Product path: vendor EGL/GLES through libhybris, Android gralloc allocations,
complete native handles and sync-files, internal presentation through hwcomposer.
No Mesa/Zink, raw KMS or nested KWin fallback.

## Android Wayland client-buffer port

The Opal launch blocker now has a host-built `android_wlegl` v2 adapter and
vendor-EGL client texture path. ARM64 incremental linking and isolated QEMU
`--version` pass; device rendering/restore qualification remains untested.
See [ANDROID-WLEGL.md](ANDROID-WLEGL.md) for implementation, artifact and limits.

The foundation notes below describe the earlier buffer-only milestone, not the
current compositor/session availability.

## Delivered foundation (historical)

- `HybrisBuffer`: owns a complete Android `EGLClientBuffer` and its vendor
  `EGL_NATIVE_BUFFER_HYBRIS` image. Noncopyable; destroys the image before the
  Android allocation. Exports render sync-files and consumes release sync-files
  with a bounded wait; a timeout is an error, not permission to recycle.
- `AquamarineBuffer`: implements the pinned Aquamarine `IBuffer` interface as
  `BUFFER_TYPE_MISC`. Exposes the native object to the future renderer bridge;
  deliberately refuses generic dma-buf/SHM attributes rather than inventing
  plane metadata. Header syntax checked against the pinned upstream sources.
- `buffer-smoke.cpp`: phone-mode-safe null-platform vendor EGL test. Creates a
  native FBO and checks every pixel through gralloc after 120 alternating
  render/export/import/wait cycles. Never acquires hwcomposer.

Device result: **PASS**, Android EGL / Adreno 640, complete native handle with
**2 fds + 22 ints**. Evidence: `artifacts/aurorahyprland-buffer-smoke.txt`.
This checks producer-fence loopback, not a real HWC consumer release fence.

Inside the guest, with this directory staged at `/root/hyprland`:

```sh
sh /root/build-hyprland-buffer.sh
```

The EGL display must outlive every buffer, and every GPU/consumer reference
must be retired before destruction. The bridge does not yet own a presentation
queue; its caller must enforce these lifetimes. Do not destroy a buffer still
owned by HWC, or recycle it after a failed fence wait.

## Source baseline

`guest/fetch-hyprland.sh <destination>` fetches Hyprland v0.49.0 and the
Aquamarine/Hyprland libraries pinned by its flake lock. It refuses dirty or
unexpected existing checkouts. It does not install an upstream DRM compositor
and pretend that it supports Android. This Aquamarine baseline matches trixie's
Wayland/xkbcommon development packages. `guest/build-hyprland.sh` builds into
`/opt/hyprland`, isolated from the working desktop. Clang 19 and the pinned
Hyprland libraries, including Aquamarine, were built/installed on the phone;
the Hyprland executable build is unfinished. No session was enabled.

The expanded on-device gate passed 1,200 render/fence/readback cycles across ten
allocations, with a stable 12 open fds. Invalid geometry/fence values were
rejected. SurfaceFlinger remained running with the same PID. Evidence:
`artifacts/aurorahyprland-buffer-retest.txt`.

## Remaining implementation gates

1. Aquamarine allocator/output backend using these Android buffers, HWC
   callbacks on the event loop, and acquire/release-fence ownership per slot.
2. Hyprland EGL initialization without GBM/device-platform assumptions, native
   EGLImage renderbuffer import, and Android Wayland client-buffer integration.
   `OpenGL.cpp` currently hardcodes GBM/device EGL displays and Linux dma-buf
   imports; setting environment variables alone cannot implement this.
3. Input via libinput with EVIOCGRAB, touch scaling and power/wake handling.
4. Launch supervision, visible frames, touch and repeated Android restore.
5. Only then enable the Hyprland manifest in the companion selector.

The current buffer adapter is **not connected to a running Hyprland renderer**.
Hyprland remains unavailable in the selector. The Android SDK is absent on
this host, so companion changes have not been APK-built or installed.
