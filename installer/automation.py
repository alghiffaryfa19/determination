"""Non-interactive operations for terminals, scripts, and optional AI agents."""
import json
from pathlib import Path
import sys

import arch
from core import Failure

COMMANDS = ('doctor', 'capabilities', 'build-plan', 'build-guest', 'inspect', 'verify', 'backup', 'restore')


def emit(event, machine=False):
    if 'log' in event:
        return
    if machine:
        print(json.dumps({'schema': 1, 'event': event}), file=sys.stderr, flush=True)
    elif 'phase' in event:
        print(f'  {event["phase"]}', file=sys.stderr, flush=True)
    elif 'stage' in event:
        print(f'  [{event["status"]}] {event["stage"]}', file=sys.stderr, flush=True)


def select_device(engine, serial=None):
    devices = engine.devices()
    ready = [d['serial'] for d in devices if d['state'] == 'device']
    if serial:
        if serial not in ready:
            raise Failure(f'Device is not authorized or connected: {serial}')
    elif len(ready) == 1:
        serial = ready[0]
    else:
        raise Failure('Select one authorized phone with --serial; found ' + str(len(ready)) + '.')
    engine.serial = serial
    return engine.inspect(serial)


def run(args, engine):
    if args.command == 'doctor':
        result = arch.doctor(engine.workspace)
    elif args.command == 'capabilities':
        result = {'schema': 1, 'ai_required': False,
                  'commands': list(COMMANDS),
                  'guest_builds': [{'distro': 'arch', 'abi': 'arm64-v8a',
                                    'renderer': 'libhybris', 'presenter': 'hwcomposer',
                                    'compositor': 'phoc', 'hardware_qualification': 'unverified'}],
                  'device_operations': ['inspect', 'backup', 'verify', 'restore'],
                  'interactive_commands': ['init', 'install', 'port', 'recovery'],
                  'boot_backend': 'Magisk-patched conventional boot image',
                  'output': 'one JSON result on stdout; JSON progress events on stderr with --json'}
    elif args.command == 'build-plan':
        result = arch.pipeline(engine, jobs=args.jobs)[0].plan()
    elif args.command == 'build-guest':
        result = arch.run(engine, jobs=args.jobs)
    else:
        if args.command == 'restore' and not args.backup:
            raise Failure('restore requires --backup with a PC-held boot backup.')
        device = select_device(engine, args.serial)
        if args.command == 'inspect':
            result = {'schema': 1, 'device': device}
        elif args.command == 'verify':
            engine.verify(device)
            result = {'schema': 1, 'status': 'verified', 'serial': engine.serial}
        elif args.command == 'backup':
            result = {'schema': 1, 'backup': str(engine.backup(device))}
        else:
            engine.restore(device, str(Path(args.backup).expanduser().resolve()))
            result = {'schema': 1, 'status': 'restored', 'serial': engine.serial}
    if args.json:
        print(json.dumps(result, sort_keys=True))
    elif 'stages' in result:
        print('\n  Aurora · Arch desktop build\n')
        for stage in result['stages']:
            print(f'  {stage["status"]:8}  {stage["label"]}')
        print(f'\n  Resume journal: {result["journal"]}')
    elif 'checks' in result:
        for check in result['checks']:
            print(f'  {"OK" if check["ok"] else "MISSING":7} {check["detail"]}')
    else:
        print(json.dumps(result, indent=2))
    return 0 if result.get('ok', True) else 1
