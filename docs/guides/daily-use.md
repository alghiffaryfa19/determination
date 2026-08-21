# Daily use

Status: current user guide
Authority: product maintainers
Last reviewed: 2026-07-30

The companion app starts internal desktop mode after confirmation. While the
guest owns the internal panel, Android framework services are paused. Return to
phone mode from the desktop launcher or power menu. The Android Quick Settings
tile is an entry control, not a reliable exit path while SurfaceFlinger is
stopped.

The external presenter is an optional development feature. A ready presenter
does not mean concurrent desktop output has passed its hardware gate.

Use the [troubleshooting guide](../operations/troubleshooting-and-qualification.md)
when mode state, guest health, or presenter status is degraded.

Application integration is installed and inspected with `det compat setup` and
`det compat check`. See the [application compatibility guide](app-compatibility.md)
for the live session contracts and remaining hardware/API limits.
