#!/usr/bin/env python3
import json, subprocess, os, time, glob

def run(*args):
    try: return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=1).decode().strip()
    except Exception: return ''

while True:
    s = {'workspace': 1, 'workspaces': [], 'title': 'Your space, beautifully quiet', 'volume': 0, 'muted': False, 'network': 'Offline', 'track': '', 'artist': '', 'battery': -1}
    if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        try:
            s['workspace'] = json.loads(run('hyprctl', 'activeworkspace', '-j'))['id']
            s['workspaces'] = [w['id'] for w in json.loads(run('hyprctl', 'workspaces', '-j'))]
            s['title'] = json.loads(run('hyprctl', 'activewindow', '-j')).get('title', s['title'])
        except Exception: pass
    v = run('wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@')
    try: s['volume'] = round(float(v.split()[1])*100)
    except Exception: pass
    s['muted'] = 'MUTED' in v
    n = run('nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active')
    s['network'] = next((l.rsplit(':',1)[0] for l in n.splitlines() if not l.endswith(':loopback')), 'Offline')
    s['track'] = run('playerctl', 'metadata', 'title')
    s['artist'] = run('playerctl', 'metadata', 'artist')
    for b in ['/sys/class/power_supply/bms/capacity', *glob.glob('/sys/class/power_supply/BAT*/capacity')]:
        try: s['battery'] = int(open(b).read())
        except Exception: pass
    print(json.dumps(s), flush=True)
    time.sleep(2)
