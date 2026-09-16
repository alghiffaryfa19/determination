#!/usr/bin/env python3
"""A shell exit must release its helpers so the host can restart the session."""
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    commands = work / 'bin'
    commands.mkdir()
    runtime = work / 'runtime'
    runtime.mkdir()
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(runtime / 'wayland-0'))
    for name, body in {
        'aurora-session-manager': 'echo $$ > "$TEST_HELPER_PID"\nexec sleep 60\n',
        'dbus-update-activation-environment': 'exit 0\n',
        'aurora-input-actions': 'exit 0\n',
        'test-shell': 'printf "%s\\n" "$SHELL" > "$TEST_SHELL_PATH"\nexit 7\n',
    }.items():
        command = commands / name
        command.write_text('#!/bin/sh\n' + body)
        command.chmod(0o755)
    source = (root / 'guest/aurora-session-launch').read_text()
    source = source.replace(
        'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        f'export PATH={commands}:/usr/bin:/bin',
    )
    launcher = work / 'launcher'
    launcher.write_text(source)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
               WAYLAND_DISPLAY='wayland-0',
               DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(runtime / 'bus'),
               TEST_HELPER_PID=str(work / 'helper.pid'),
               TEST_SHELL_PATH=str(work / 'shell.path'),
               SHELL='/system/bin/sh')
    process = subprocess.Popen(['sh', str(launcher), 'client', str(commands / 'test-shell')],
                               env=env, start_new_session=True)
    try:
        assert process.wait(timeout=8) == 7, 'shell exit status was lost'
        uid = os.getuid()
        expected_shell = next(
            fields[6] for fields in
            (line.rstrip('\n').split(':') for line in Path('/etc/passwd').read_text().splitlines())
            if int(fields[2]) == uid
        )
        assert (work / 'shell.path').read_text().strip() == expected_shell, 'Android SHELL leaked into guest client session'
        helper = int((work / 'helper.pid').read_text())
        try:
            os.kill(helper, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError('session helper survived shell exit')
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        listener.close()
print('session launcher shell-exit recovery passed')
