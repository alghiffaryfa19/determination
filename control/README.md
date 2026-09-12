# Aurora control plane

This directory contains the host-side bionic control-plane foundation:

- `aurorad`: the single state/API owner;
- `auroractl`: the reference CLI and protocol client;
- `aurora-guest-agent`: Debian/glibc health reporter and capability-scoped guest
  client;
- `libauroracontrol`: versioned protocol, durable state, system probes and the
  bounded fixed-argv adapter runner.

The first deployment starts `aurorad` in observe-only mode. Mutating mode requests
are rejected until transition ownership and device recovery tests pass. The
existing `desktop-on`, `desktop-off`, and `guest-start` scripts remain the
proven transition implementation during migration.

The transition controller is nevertheless built and testable behind the
explicit `--allow-transitions` daemon flag. It journals `guest-start`,
`desktop-on`, and `desktop-off` as fixed-argv adapters, coalesces duplicate
requests, rejects conflicts, enforces deadlines, rolls failed entries back to
phone mode, and marks interrupted transitions for recovery on restart. Boot
packaging does not enable that flag yet.

Build and test on the host, then cross-build for Android arm64:

```sh
./control/build.sh host
./control/build.sh android
./control/build.sh guest
```

For an isolated host smoke test:

```sh
root=$(mktemp -d)
mkdir -p "$root/run" "$root/state"
./control/build/host/aurorad --root "$root" --foreground &
./control/build/host/auroractl --root "$root" doctor --json
```

Once a test daemon is intentionally transition-enabled:

```sh
auroractl mode desktop --wait --deadline 120
auroractl mode phone --wait --deadline 60
auroractl recover --wait
```

The daemon also creates `/data/aurora/run/control/aurorad.sock`, which the
existing LXC bind exposes as `/mnt/aurora-control/aurorad.sock`. Only host uid 0 and
the unmapped guest uid 1000 may connect. That endpoint may report guest health
and request PHONE/recovery; it may never request DESKTOP. The old command-file
host agent remains a migration fallback for power actions and observe-only
deployments.

Protocol and state details are documented in
[`docs/platform-overhaul.md`](../docs/platform-overhaul.md).
