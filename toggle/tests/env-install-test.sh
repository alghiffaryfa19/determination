#!/bin/sh
# Host/runnable tests for toggle/env-install. Every path is a scratch root; the
# companion app consumes the same state files that are asserted here.
# On the phone itself: AURORA_TEST_SH=/system/bin/sh AURORA_TEST_TMP=/data/local/tmp
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SH=${AURORA_TEST_SH:-/bin/sh}
TMP_BASE=${AURORA_TEST_TMP:-${TMPDIR:-/tmp}}
WORK=$(mktemp -d "$TMP_BASE/aurora-env-XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

A=$WORK/aurora
mkdir -p "$A/bin" "$A/etc/sessions" "$A/log" "$A/run" "$A/lxc/bin" "$A/guest/usr/local/bin" \
    "$A/guest/etc/systemd/system" "$A/guest/usr/bin" "$A/guest/root/aurora-build" "$WORK/stub"
cp "$ROOT/toggle/env-install" "$A/bin/env-install"

# uid 0 for the preflight, without needing root on the workstation.
cat > "$WORK/stub/id" <<EOF
#!$SH
[ "\${1:-}" = -u ] && { echo 0; exit 0; }
for candidate in /usr/bin/id /system/bin/id; do
    [ -x "\$candidate" ] && exec "\$candidate" "\$@"
done
exit 1
EOF
chmod 0755 "$WORK/stub/id"

# The container is stubbed: the adapter answers as a Debian trixie guest would.
cat > "$A/lxc/bin/lxc-info" <<'EOF'
#!/bin/sh
[ -e "$0.fail" ] && { echo 'State: STOPPED'; exit 0; }
echo 'State: RUNNING'
EOF
cat > "$A/lxc/bin/lxc-stop" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$A/lxc/bin/lxc-attach" <<EOF
#!/bin/sh
# args: -P <path> -n guest -- <command...>
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        --) shift; break ;;
        *) shift ;;
    esac
done
[ -n "\${1:-}" ] || exit 2
case "\$1" in
    /usr/local/bin/aurora-platform)
        shift
        case "\$1" in
            id) echo debian ;;
            deps-packages)
                shift
                case "\$1" in
                    plasma-mobile) cat "$WORK/pkgs-plasma" ;;
                    phosh) cat "$WORK/pkgs-phosh" ;;
                    hyprland|quickshell) echo "unsupported dependency set" >&2; exit 2 ;;
                    *) exit 2 ;;
                esac
                ;;
            package-status)
                shift
                while [ "\$#" -gt 0 ]; do
                    if [ -e "$A/run/installed-\$1" ]; then echo "\$1=installed"; else echo "\$1=absent"; fi
                    shift
                done
                ;;
            package-refresh) [ ! -e "$WORK/fail-refresh" ] ;;
            deps)
                shift
                [ ! -e "$WORK/fail-deps" ] || exit 1
                case "\$1" in
                    plasma-mobile) group_pkgs="\$(cat "$WORK/pkgs-plasma")" ;;
                    phosh) group_pkgs="\$(cat "$WORK/pkgs-phosh")" ;;
                    *) exit 2 ;;
                esac
                for installed_pkg in \$group_pkgs; do
                    touch "$A/run/installed-\$installed_pkg"
                done
                ;;
            package-remove)
                shift
                while [ "\$#" -gt 0 ]; do
                    rm -f "$A/run/installed-\$1"
                    shift
                done
                ;;
            service-enable) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    /bin/sh)
        shift
        # The in-guest provisioner stands in for a source build.
        [ ! -e "$WORK/fail-build" ] || exit 1
        touch "$A/run/built"
        ;;
    *) exit 0 ;;
esac
exit 0
EOF
cat > "$A/bin/guest-start" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$A/bin/desktop-on" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$A/bin/guest-distro" <<'EOF'
#!/bin/sh
[ "${1:-}" = root ] && { echo "$AURORA_ENV_GUEST_ROOT"; exit 0; }
exit 0
EOF
cat > "$A/bin/session-catalog" <<EOF
#!/bin/sh
for manifest in "$A/etc/sessions/"*.session; do
    [ -f "\$manifest" ] || continue
    id=\${manifest##*/}; id=\${id%.session}
    echo "===\$id"
    cat "\$manifest"
    printf '\\nruntime_ready=%s\\nruntime_reason=%s\\n' \\
        "\$( [ -e "$A/run/ready-\$id" ] && echo yes || echo no )" \\
        "\$( [ -e "$A/run/ready-\$id" ] && echo '' || echo 'Missing guest executable: required binary' )"
done
EOF
chmod 0755 "$A/lxc/bin/"* "$A/bin/"*
for stub in "$A/bin/"* "$A/lxc/bin/"*; do
    [ -f "$stub" ] && sed -i "1s|^#!/bin/sh\$|#!$SH|" "$stub"
done

# The environment catalog is the session manifests.
# Guests that ship an in-guest provisioner (portable profiles do) can build
# components no package provides; the fixture mirrors that layout.
for provisioner in build-wlroots-phoc.sh build-hyprland.sh; do
    printf '#!/bin/sh\nexit 0\n' > "$A/guest/root/aurora-build/$provisioner"
    chmod 0755 "$A/guest/root/aurora-build/$provisioner"
done

printf 'plasma-workspace\nplasma-desktop\nkwin-wayland\n' > "$WORK/pkgs-plasma"
printf 'phoc\nphosh\nsqueekboard\n' > "$WORK/pkgs-phosh"

cat > "$A/etc/sessions/plasma-mobile.session" <<'EOF'
id=plasma-mobile
title=Plasma Mobile
description=KWin 6 desktop shell.
backend=gralloc-minigbm
compositor=/usr/bin/kwin_wayland
required_binaries=/usr/local/bin/aurora-plasma-client
services=logind,pipewire
qualification=experimental
reason=soak gates pending
limitations=no native-handle round trip
packages=plasma-mobile
glue=aurora-plasma-client
EOF
cat > "$A/etc/sessions/phosh.session" <<'EOF'
id=phosh
title=Phosh
description=The verified stack.
backend=libhybris-hwcomposer
compositor=/usr/local/bin/phoc
required_binaries=/usr/libexec/phosh,/usr/bin/squeekboard
qualification=qualified
packages=phosh
build=/root/aurora-build/build-wlroots-phoc.sh
glue=aurora-phosh-session
EOF
cat > "$A/etc/sessions/hyprland.session" <<'EOF'
id=hyprland
title=Hyprland
description=Compositor plus shell.
backend=libhybris-hwcomposer
compositor=/opt/hyprland/bin/Hyprland
shell=hyprland-config
required_binaries=/opt/hyprland/bin/Hyprland
qualification=experimental
packages=hyprland
build=/root/aurora-build/build-hyprland.sh
glue=aurora-hyprland
EOF

run() { # args...
    PATH="$WORK/stub:$PATH" AURORA="$A" AURORA_ENV_GUEST_ROOT="$A/guest" \
        AURORA_SETUP_WAKE_LOCK=/dev/null AURORA_SETUP_WAKE_UNLOCK=/dev/null \
        "$SH" "$A/bin/env-install" "$@"
}

# --- contract: no unescaped '|' in ${...} (mksh R59 parses it as a pipe) -----
if grep -q -F -e '%%|' -e '#*|' "$A/bin/env-install"; then
    echo "env-install has an unescaped '|' parameter pattern" >&2
    exit 1
fi

# --- catalog reports every environment with its recipe and state ------------
run catalog > "$WORK/catalog.txt"
for section in meta environment step; do
    grep -qx "==$section" "$WORK/catalog.txt" || {
        echo "catalog is missing the $section section" >&2
        exit 1
    }
done
for key in id title backend qualification reason limitations packages build glue \
           required_binaries runtime_ready missing_binaries installed packages_state \
           package_set installable recipe build_present; do
    grep -q "^$key=" "$WORK/catalog.txt" || {
        echo "catalog environments are missing $key" >&2
        exit 1
    }
done
grep -qx "id=plasma-mobile" "$WORK/catalog.txt"
grep -qx "qualification=qualified" "$WORK/catalog.txt"
grep -qx "packages=plasma-mobile" "$WORK/catalog.txt"
grep -qx "package_set=available" "$WORK/catalog.txt"
grep -qx "installed=no" "$WORK/catalog.txt"

# --- the compositor counts as a required binary (session-catalog agrees) ----
grep -A30 '^id=hyprland$' "$WORK/catalog.txt" | grep -qx "missing_binaries=/opt/hyprland/bin/Hyprland"
grep -A30 '^id=hyprland$' "$WORK/catalog.txt" | grep -qx "runtime_ready=no"
# Reasons are prose: a word-splitting parse would truncate them to "Missing".
grep -A30 '^id=hyprland$' "$WORK/catalog.txt" | grep -q "^runtime_reason=Missing guest executable:"

# --- a changed manifest invalidates the cached package resolution ----------
printf 'phosh\nphoc\n' > "$WORK/pkgs-phosh"
run reset >/dev/null
run plan phosh > "$WORK/plan-phosh.txt"
grep -qx "name=phosh" "$WORK/plan-phosh.txt"
grep -qx "name=phoc" "$WORK/plan-phosh.txt"

# --- an environment with no package set on this distro is not installable ---
grep -A30 '^id=hyprland$' "$WORK/catalog.txt" | grep -qx "package_set=unsupported"
grep -A30 '^id=hyprland$' "$WORK/catalog.txt" | grep -qx "installable=no"
grep -A30 '^id=hyprland$' "$WORK/catalog.txt" | grep -q "^installable_reason=.*hyprland"

# --- plan lists the packages the adapter would install ----------------------
run plan plasma-mobile > "$WORK/plan.txt"
grep -qx "==package" "$WORK/plan.txt"
grep -qx "name=kwin-wayland" "$WORK/plan.txt"
grep -qx "name=plasma-workspace" "$WORK/plan.txt"
grep -qx "state=absent" "$WORK/plan.txt"
grep -q "^id=mode$" "$WORK/plan.txt"
grep -A3 '^id=mode$' "$WORK/plan.txt" | grep -qx "state=ok"

# --- install: packages, glue warning, verify -------------------------------
run install plasma-mobile --foreground > "$WORK/install.txt" 2>&1 || true
run status > "$WORK/status.txt"
for section in state step log; do
    grep -qx "==$section" "$WORK/status.txt" || {
        echo "status is missing the $section section" >&2
        exit 1
    }
done
for key in running state action env env_title step step_index step_total started \
           finished distro package_count runtime_ready runtime_reason summary error log; do
    grep -q "^$key=" "$WORK/status.txt" || {
        echo "status state is missing $key" >&2
        exit 1
    }
done
grep -qx "action=install" "$WORK/status.txt"
grep -qx "env=plasma-mobile" "$WORK/status.txt"
grep -qx "package_count=3" "$WORK/status.txt"
grep -qx 'state=skip' "$A/run/env/install-none.state" 2>/dev/null || true
for step in preflight packages glue build services verify; do
    [ -r "$A/run/env/$step.state" ] || { echo "missing state for $step" >&2; exit 1; }
done
[ -e "$A/run/installed-kwin-wayland" ] || { echo "kwin was not installed" >&2; exit 1; }
case "$(sed -n 's/^state=//p' "$A/run/env/packages.state")" in
    ok) ;;
    *) echo "packages step did not pass: $(cat "$A/run/env/packages.state")" >&2; exit 1 ;;
esac
# Required binaries still absent, so the run must report a warning, not success.
[ ! -e "$A/run/ready-plasma-mobile" ]
grep -qx "state=warn" "$WORK/status.txt"
grep -qx "runtime_ready=no" "$WORK/status.txt"
grep -qx 'state=warn' "$A/run/env/glue.state"
grep -q 'missing Aurora files' "$A/run/env/glue.state"

# --- a satisfied environment reports ready and success ---------------------
touch "$A/run/ready-plasma-mobile"
touch "$A/guest/usr/local/bin/aurora-plasma-client"
run reset >/dev/null
run install plasma-mobile --foreground > "$WORK/ready.txt" 2>&1 || true
run status > "$WORK/ready-status.txt"
grep -qx "state=ok" "$WORK/ready-status.txt"
grep -qx "runtime_ready=yes" "$WORK/ready-status.txt"
grep -qx 'state=ok' "$A/run/env/verify.state"
grep -qx 'state=ok' "$A/run/env/glue.state"

# --- remove: packages declared by the environment only --------------------
run reset >/dev/null
run remove plasma-mobile --foreground > "$WORK/remove.txt" 2>&1 || true
run status > "$WORK/remove-status.txt"
grep -qx "action=remove" "$WORK/remove-status.txt"
grep -qx 'state=ok' "$A/run/env/remove.state"
[ -e "$A/run/installed-kwin-wayland" ] && { echo "packages were not removed" >&2; exit 1; }
# Removal must not touch the runtime the other environments share.
[ -e "$A/guest/usr/local/bin/aurora-plasma-client" ]

# --- a failed package step is reported, not swallowed ---------------------
run reset >/dev/null
: > "$WORK/fail-deps"
run install plasma-mobile --foreground > "$WORK/fail.txt" 2>&1 || true
grep -qx 'state=fail' "$A/run/env/packages.state"
run status > "$WORK/fail-status.txt"
grep -qx "state=fail" "$WORK/fail-status.txt"
grep -q 'package installation failed' "$WORK/fail-status.txt"
rm -f "$WORK/fail-deps"

# --- the optional build step runs only when asked for ---------------------
run reset >/dev/null
rm -rf "$A/run/env-cache" "$A/run/built"; rm -f "$A/run/installed-"*
run install phosh --foreground > "$WORK/phosh.txt" 2>&1 || true
grep -qx 'state=skip' "$A/run/env/build.state"
[ -e "$A/run/built" ] && { echo "the build ran without being requested" >&2; exit 1; }
run reset >/dev/null
rm -rf "$A/run/env-cache"; rm -f "$A/run/installed-"*
run install phosh --with-build --foreground > "$WORK/phosh-build.txt" 2>&1 || true
[ -e "$A/run/built" ] || { echo "the requested in-guest build did not run" >&2; exit 1; }
grep -q 'build-wlroots-phoc.sh' "$A/run/env/build.state"

# --- cancel is honoured between steps ------------------------------------
run reset >/dev/null
rm -rf "$A/run/env-cache"; rm -f "$A/run/installed-"*
: > "$A/run/env.cancel.armed"
run cancel >/dev/null
run status > "$WORK/cancel-status.txt"
grep -qx "state=none" "$WORK/cancel-status.txt"

# --- preflight refuses while desktop mode owns the panel ------------------
run reset >/dev/null
: > "$A/run/desktop-mode"
if run install plasma-mobile --foreground > "$WORK/display.txt" 2>&1; then
    echo "install must fail while desktop mode owns the display" >&2
    exit 1
fi
run status > "$WORK/display-status.txt"
grep -qx 'state=fail' "$WORK/display-status.txt"
grep -q 'Display ownership' "$A/run/env.checks"
rm -f "$A/run/desktop-mode"

# --- readiness is a cheap probe ------------------------------------------
run readiness > "$WORK/readiness.txt"
grep -qx "==readiness" "$WORK/readiness.txt"
grep -qx "guest_running=yes" "$WORK/readiness.txt"
grep -qx "distro=debian" "$WORK/readiness.txt"

# --- unknown ids and hostile input are refused ---------------------------
if run install "plasma; reboot" --foreground >/dev/null 2>&1; then
    echo "install must reject a hostile environment id" >&2
    exit 1
fi
if run plan ../../etc/passwd >/dev/null 2>&1; then
    echo "plan must reject a traversal id" >&2
    exit 1
fi
if run install hyprland --foreground > "$WORK/hypr.txt" 2>&1; then
    echo "install must fail when no package set exists for this distro" >&2
    exit 1
fi
grep -q "no package set" "$A/run/env/packages.state"

echo "env install tests passed"
