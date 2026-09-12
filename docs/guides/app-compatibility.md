# Application compatibility

Status: core session contract device-qualified on Debian; broad app matrix ongoing
Authority: guest session maintainers
Last reviewed: 2026-08-21

Aurora's compatibility layer gives applications the same session
contracts they expect from a conventional Phosh distribution. Rendering a
shell is not enough: logind must know the user is logged in, D-Bus activation
must inherit the Wayland environment, portals must have a Phosh backend, and
settings must belong to the desktop user rather than root.

## Install or refresh

From phone mode with the guest running and networked:

```sh
aurora compat setup
```

This installs the portal, Secret Service, accessibility, GVfs, Flatpak, MIME,
font, and XDG user-directory runtime. It also installs the PAM-backed
`aurora-phosh.service`. The service is started only during desktop mode.

Fresh Debian rootfs builds include these packages. Portable Arch and Alpine
profiles invoke the same setup through their distro adapter, but remain subject
to the qualification boundaries in [guest distro profiles](guest-distros.md).

## What applications see

`aurora-phosh-session` publishes one canonical environment to launched programs
and D-Bus-activated services:

- `XDG_CURRENT_DESKTOP=Phosh:GNOME`, a Wayland user session, and the standard
  Phosh/GNOME desktop identifiers;
- native Wayland selection for GTK, Qt, and Firefox;
- XDG portals for file choosing, screenshots, URI opening, and sandboxed apps;
- Secret Service, accessibility bus, feedback service, user folders, MIME and
  desktop-entry databases;
- libhybris Wayland EGL for applications, with GTK4 on its GLES renderer.

Firefox keeps touch-sized browser chrome while defaulting web content to 67%
on the 3x-scaled internal panel. This gives fixed-width desktop pages more
useful layout room without overwriting site-specific zoom or a global value the
user selected later in Firefox Settings.

The compositor remains separate from the application session. This is
intentional: `phoc -E` is incompatible with the half-backported pidfd ABI on
the qualified downstream 4.14 kernel.

## Verify a live session

Enter desktop mode, then run from the host:

```sh
aurora compat check
```

The check distinguishes required failures from optional warnings and verifies
the live logind, D-Bus, portal, graphics, accessibility, secrets, Flatpak, and
URI-handler contracts. Package presence alone does not count as a pass.

On 2026-08-21 the qualified Debian guest passed all 17 live checks on
`guacamoleb`; GNOME Calculator also launched through its installed desktop entry
with the compatibility graphics environment. This proves the session contract,
not a blanket pass for every application.

## Limits

This layer makes well-behaved adaptive GTK/libadwaita applications respond to
the phone-sized surface and lets sandboxed apps integrate correctly. It cannot
make a fixed-width desktop UI adaptive; that requires an upstream responsive UI
or an application-specific patch. Hardware APIs also remain separate work:
camera, modem/SMS, location, Bluetooth, suspend, and every direct-audio route
need explicit Aurora bridges or qualification.

Internal desktop mode still freezes Android `system_server`, so Android-backed
portal implementations are not viable there. External convergence may later
add Android-mediated integrations while keeping this Linux session contract.
