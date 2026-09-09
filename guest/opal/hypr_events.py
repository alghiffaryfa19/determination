"""Event-driven Hyprland adapter; independent of slow system-status polling."""
import json
import os
import pathlib
import select
import socket
import time


def listen(emit):
    signature = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    if not signature:
        return
    base = pathlib.Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'hypr' / signature
    if not (base / '.socket2.sock').exists():
        base = pathlib.Path('/tmp/hypr') / signature

    def query(name):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(0.5)
            client.connect(str(base / '.socket.sock'))
            client.sendall(('j/' + name).encode())
            chunks = []
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
            return json.loads(b''.join(chunks))

    def patch(data):
        emit({'event': 'compositor', 'data': data})

    def refresh(initial=False):
        # Do not overwrite event-driven focus with a background snapshot.
        data = {
            'workspaces': [w['id'] for w in query('workspaces') if w['id'] > 0],
            'windows': [
                {'title': w['title'], 'className': w['class'],
                 'address': w['address'], 'workspace': w['workspace']['id']}
                for w in query('clients') if w.get('mapped')
            ],
        }
        if initial:
            focused = query('activewindow')
            workspace = query('activeworkspace')
            data.update(hypr=True, workspace=workspace['id'], activeMonitor=workspace.get('monitor', ''),
                        title=focused.get('title', 'Your desktop'), activeAddress=focused.get('address', ''))
        patch(data)

    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events:
                events.connect(str(base / '.socket2.sock'))
                # Subscribe first so transitions during initialization aren't lost.
                refresh(initial=True)
                buffer = b''
                deadline = None
                while True:
                    timeout = None if deadline is None else max(0, deadline - time.monotonic())
                    if select.select([events], [], [], timeout)[0]:
                        chunk = events.recv(65536)
                        if not chunk:
                            break
                        buffer += chunk
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            event, _, payload = line.decode(errors='replace').partition('>>')
                            if event == 'workspacev2':
                                patch({'workspace': int(payload.split(',', 1)[0])})
                            elif event == 'focusedmonv2':
                                patch({'workspace': int(payload.split(',', 1)[1]), 'activeMonitor': payload.split(',', 1)[0]})
                            elif event == 'focusedmon':
                                # Also supports Hyprland releases without focusedmonv2.
                                patch({'workspace': query('activeworkspace')['id'], 'activeMonitor': payload.split(',', 1)[0]})
                            elif event == 'activewindow':
                                patch({'title': payload.partition(',')[2] or 'Your desktop'})
                            elif event == 'activewindowv2':
                                patch({'activeAddress': ('0x' + payload.removeprefix('0x')) if payload else ''})
                            if event in {'createworkspace', 'createworkspacev2', 'destroyworkspace',
                                         'destroyworkspacev2', 'moveworkspace', 'moveworkspacev2',
                                         'renameworkspace', 'openwindow', 'closewindow', 'movewindow',
                                         'movewindowv2', 'windowtitle', 'windowtitlev2',
                                         'monitoradded', 'monitorremoved', 'configreloaded'}:
                                if deadline is None:
                                    deadline = time.monotonic() + 0.025
                    if deadline is not None and time.monotonic() >= deadline:
                        refresh()
                        deadline = None
        except (OSError, ValueError, KeyError, TypeError):
            pass
        # Reconnect without busy-looping if the compositor socket goes away.
        time.sleep(1)
