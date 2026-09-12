# Android Wayland client buffers

## Host-built adapter

`AndroidWlegl.cpp` implements `android_wlegl` v2 for the pinned Hyprland
9958d297641b5c84dcff93f9039d80a5ad37ab00 / Aquamarine 0.8.0 port.
`patches/hyprland-android-wlegl.patch` adds protocol generation, library linkage,
registration under `AURORA_HYBRIS`, and native-buffer texture import.
`guest/patch-aurorahyprland.sh` copies the adapter/XML and applies the patch after
the existing Hyprland patches.

Both allocation paths create Hyprland's generated `CWlBuffer`, wrapped by
`CWLBufferResource` and an `IHLBuffer`. There is no raw `wl_buffer` passed into
Hyprland's generated-resource casts.

- Client allocation: validate geometry, handle sizes and fd count, import the
  complete native handle through libhybris gralloc, and retain the imported
  object independently of the temporary protocol handle.
- Server allocation: allocate through gralloc, send every fd/private integer,
  and send the server-created `wl_buffer` through the v2 reply.
- Rendering: import the native Android object with `EGL_NATIVE_BUFFER_HYBRIS`,
  then bind its vendor EGLImage as a GLES texture. No synthetic dma-buf planes.
- Ownership: protocol handle destruction closes received fds; native object
  references release imported and allocated handles through their respective
  gralloc release paths. Buffer resources stay owned until their destroy event;
  surface references can keep the underlying buffer alive after that event.
- Release: v2 has no release-fence event. The adapter conservatively finishes
  compositor GLES reads before `wl_buffer.release`. This is a correctness-first
  synchronization point, not a claim of an asynchronous explicit-fence client
  transport. The existing Aquamarine/HWC producer and release fences are unchanged.

The client-side producer synchronization behavior and buffer-reuse safety still
require device qualification, as do rendering, resource-disconnect cleanup and
repeated Android restore. Do not describe this as an on-panel Opal success yet.

## Validation performed

- All six Hyprland patches apply in order to a fresh pinned worktree.
- Adapter, Texture.cpp and ProtocolManager.cpp pass host Clang syntax checks
  against the guest's pinned dependency/protocol headers.
- The three changed translation units and generated protocol C code compile
  with the cached Debian ARM64 cross-toolchain.
- Incremental ARM64 executable links successfully against captured guest build
  objects and libraries. This is **not** a full clean-source rebuild.
- The resulting executable runs `--version` under QEMU in an isolated container,
  with a private runtime directory, reporting Hyprland 0.49.0 and the expected
  pinned libraries. This tests loader/ABI startup, not EGL or presentation.

Artifact: `build/aurorahyprland-wlegl-cross/Hyprland` (about 15 MB).
SHA256: `7b7441d4856d62e0f19311fb9bf165481ecf6e1d09951bc71cda6e0d17ad459a`.
Logs: `build/aurorahyprland-src/wlegl-cross-build.log` and
`build/aurorahyprland-src/wlegl-arm64-version.log`.

The guest was stopped during this work. Reads captured headers, libraries and
cached compositor objects via root ADB tar streams; no guest startup, executable
replacement, session selection or host Opal deployment was performed.

## Rebuild from the captured workspace

```
python3 guest/build-aurorahyprland-wlegl-cross.py
```

The script requires the captured `build/aurorahyprland-sysroot` tree (guest
`usr/include`, `usr/local/include`, `usr/local/lib`, `usr/lib/aarch64-linux-gnu`,
`opt/aurorahyprland/include`, `opt/aurorahyprland/lib`, and the pinned Hyprland generated
protocols/build-aurora), plus the patched host Hyprland checkout. It copies the
current adapter, generates protocol code, recompiles the changed units and
reuses the unmodified cached objects. It neither installs nor launches anything.
For a clean guest-source build, the normal patch/build scripts now include the
adapter; that build path has not yet been executed with this patch.
