# Dethyprland bring-up

Product path: vendor EGL/GLES through libhybris, Android gralloc allocations,
complete native handles and sync-files, internal presentation through hwcomposer.
No Mesa/Zink, raw KMS or nested KWin fallback.

## Delivered foundation

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
**2 fds + 22 ints**. Evidence: `artifacts/dethyprland-buffer-smoke.txt`.
This checks producer-fence loopback, not a real HWC consumer release fence.

Inside the guest, with this directory staged at `/root/dethyprland`:

```sh
sh /root/build-dethyprland-buffer.sh
```

The EGL display must outlive every buffer, and every GPU/consumer reference
must be retired before destruction. The bridge does not yet own a presentation
queue; its caller must enforce these lifetimes. Do not destroy a buffer still
owned by HWC, or recycle it after a failed fence wait.

## Source baseline

`guest/fetch-dethyprland.sh <destination>` fetches Hyprland v0.54.3 and the
Aquamarine/Hyprland libraries pinned by its flake lock. It refuses dirty or
unexpected existing checkouts. It does not install an upstream DRM compositor
and pretend that it supports Android. This baseline requires a C++26-capable
compiler and newer Wayland/input development dependencies than stock trixie.

## Remaining implementation gates

1. Aquamarine allocator/output backend using these Android buffers, HWC
   callbacks on the event loop, and acquire/release-fence ownership per slot.
2. Hyprland EGL initialization without GBM/device-platform assumptions, native
   EGLImage renderbuffer import, and Android Wayland client-buffer integration.
   `OpenGL.cpp` currently hardcodes GBM/device EGL displays and Linux dma-buf
   imports; setting environment variables alone cannot implement this.
3. Input via libinput with EVIOCGRAB, touch scaling and power/wake handling.
4. Launch supervision, visible frames, touch and repeated Android restore.
5. Only then enable the Dethyprland manifest in the companion selector.

The current buffer adapter is **not connected to a running Hyprland renderer**.
Dethyprland remains unavailable in the selector. The Android SDK is absent on
this host, so companion changes have not been APK-built or installed.
