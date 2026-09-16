#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
sessions=
cleanup() {
    for pid in $sessions; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$WORK/bin" "$WORK/runtime"
touch "$WORK/claimed"
cat > "$WORK/bin/fake-audio-process" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$$" >> "$AURORA_TEST_STARTS"
trap 'exit 0' HUP INT TERM
while :; do sleep 1; done
EOF
chmod 0755 "$WORK/bin/fake-audio-process"
for command in pipewire pipewire-pulse wireplumber; do
    ln -s fake-audio-process "$WORK/bin/$command"
done

start_session() {
    AURORA_AUDIO_MARKER="$WORK/claimed" \
    XDG_RUNTIME_DIR="$WORK/runtime" \
    AURORA_TEST_STARTS="$WORK/starts" \
    PATH="$WORK/bin:$PATH" \
        "$ROOT/guest/aurora-audio-session" &
    session_pid=$!
    sessions="$sessions $session_pid"
}

wait_for() {
    tries=0
    until "$@"; do
        tries=$((tries + 1))
        [ "$tries" -lt 100 ] || return 1
        sleep 0.05
    done
}

owner_is_first() {
    [ "$(cat "$WORK/runtime/aurora-audio-session.lock/owner" 2>/dev/null || true)" = "$first" ]
}
graph_started_once() {
    [ -f "$WORK/starts" ] && [ "$(wc -l < "$WORK/starts")" -eq 3 ]
}
owner_is_third() {
    [ "$(cat "$WORK/runtime/aurora-audio-session.lock/owner" 2>/dev/null || true)" = "$third" ]
}

start_session
first=$session_pid
wait_for owner_is_first
wait_for graph_started_once

# A compositor/client retry must not create another audio supervisor or graph.
start_session
second=$session_pid
wait "$second"
sleep 0.2
[ "$(cat "$WORK/runtime/aurora-audio-session.lock/owner")" = "$first" ]
[ "$(wc -l < "$WORK/starts")" -eq 3 ]

# The owner releases its lock on shutdown and a later session may take over.
kill -TERM "$first"
wait "$first"
wait_for test ! -d "$WORK/runtime/aurora-audio-session.lock"
start_session
third=$session_pid
wait_for owner_is_third

echo "audio session singleton: PASS"
