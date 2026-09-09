"""Read-only Linux joystick mapping; no grabs, injection or permission changes."""
import array
from pathlib import Path


def device_maps(device):
    import fcntl
    def read_map(request, kind, length):
        values = array.array(kind, [0] * length)
        try:
            fcntl.ioctl(device.fileno(), request, values)
            return values
        except OSError:
            return None
    # Query independently: one unsupported ioctl must not discard the other map.
    return read_map(0x84006a34, 'H', 512), read_map(0x80406a32, 'B', 64)


def device_info(path, root=Path('/sys/class/input')):
    device = Path(root) / Path(path).name / 'device'
    def read(key):
        try:
            return (device / key).read_text().strip()
        except OSError:
            return ''
    name, vendor, product = read('name'), read('id/vendor'), read('id/product')
    return {'name': name, 'vendor': vendor, 'product': product,
            'virtual': vendor == '28de' and product == '11ff' or
                       '/devices/virtual/' in str(device.resolve())}


def ranked_devices(paths):
    # Steam Input may create jsN before the real controller. Never consume both.
    return sorted(paths, key=lambda p: (device_info(p)['virtual'], str(p)))


def family(name='', vendor=''):
    name = name.lower()
    if 'stadia' in name or vendor == '18d1':
        return 'stadia'
    if vendor == '054c' or any(s in name for s in ('dualsense', 'dualshock', 'playstation', 'sony interactive')):
        return 'playstation'
    if vendor == '057e' or any(s in name for s in ('nintendo', 'joy-con', 'switch pro')):
        return 'nintendo'
    if vendor == '045e' or any(s in name for s in ('xbox', 'x-box', 'xinput')):
        return 'xbox'
    return 'generic'


def effective_layout(layout, profile):
    return ('nintendo' if profile == 'nintendo' else 'standard') if layout == 'auto' else layout


def button_action(number, layout='standard', codes=None, profile='generic'):
    semantic = {304: 'accept', 305: 'back', 307: 'search', 308: 'pin',
                310: 'previousTab', 311: 'nextTab', 312: 'pageUp', 313: 'pageDown',
                314: 'menu', 315: 'home', 316: 'home',
                317: 'search', 318: 'menu',
                544: 'up', 545: 'down', 546: 'left', 547: 'right'}
    # Stadia Bluetooth exposes auxiliary buttons as TRIGGER_HAPPY codes.
    # Open the hub rather than guessing which is Capture or Assistant.
    if profile == 'stadia':
        semantic.update({code: 'menu' for code in range(704, 708)})
    fallback = {0: 'accept', 1: 'back', 2: 'pin', 3: 'search',
                4: 'previousTab', 5: 'nextTab', 6: 'menu', 7: 'home',
                8: 'home', 9: 'search', 10: 'menu'}
    if number < 0:
        return None
    # Unknown/out-of-range kernel codes must not become guessed face buttons.
    action = (semantic.get(codes[number]) if number < len(codes) else None) if codes is not None else fallback.get(number)
    if effective_layout(layout, profile) == 'nintendo':
        action = {'accept': 'back', 'back': 'accept', 'pin': 'search', 'search': 'pin'}.get(action, action) if (codes is None and number < 4 or codes is not None and number < len(codes) and codes[number] in (304,305,307,308)) else action
    return action


def axis_code(number, codes=None):
    if number < 0:
        return None
    return (codes[number] if number < len(codes) else None) if codes is not None else {0: 0, 1: 1, 6: 16, 7: 17}.get(number)


def axis_orientation(number, codes=None):
    code = axis_code(number, codes)
    return 'horizontal' if code in (0, 16) else 'vertical' if code in (1, 17) else None


class NavigationState:
    """Hysteresis, repeat and trigger edges, including safe startup snapshots."""
    def __init__(self, buttons=None, axes=None, profile='generic'):
        self.buttons, self.axes, self.profile = buttons, axes, profile
        self.states, self.held, self.blocked = {}, {}, set()
        self.trigger_rest = {}

    def feed(self, kind, number, value, now, layout='auto'):
        initial, kind = bool(kind & 0x80), kind & 0x7f
        token = (kind, number)
        if kind == 1:
            key = button_action(number, layout, self.buttons, self.profile)
            state = bool(value)
        elif kind == 2:
            code = axis_code(number, self.axes)
            orientation = axis_orientation(number, self.axes)
            if orientation:
                old = self.states.get(token, 0)
                threshold = 10000 if old else 18000
                state = 0 if abs(value) < threshold else (1 if value > 0 else -1)
                key = ('right' if state > 0 else 'left') if orientation == 'horizontal' else ('down' if state > 0 else 'up')
            else:
                trigger_codes = (10, 9) if self.profile == 'stadia' else (2, 5) if self.profile in ('xbox', 'playstation') else ()
                if code not in trigger_codes:
                    return []
                # JS drivers normalize both signed/unsigned hardware to signed
                # values; some virtual drivers instead rest at zero.
                if initial:
                    self.trigger_rest[number] = -32767 if value < -16000 else 0
                rest = self.trigger_rest.get(number, -32767)
                progress = (value - rest) / (32767 - rest)
                state = progress > (.35 if self.states.get(token) else .65)
                key = 'pageUp' if code == trigger_codes[0] else 'pageDown'
        else:
            return []
        old = self.states.get(token, 0)
        self.states[token] = state
        if initial:
            if state:
                self.blocked.add(token)
            return []
        if not state:
            self.blocked.discard(token)
            self.held.pop(token, None)
            return []
        if token in self.blocked or state == old or not key:
            return []
        if key in ('up', 'down', 'left', 'right'):
            self.held[token] = (key, now + .38)
        return [key]

    def repeat(self, now):
        result = []
        for token, (key, due) in list(self.held.items()):
            if now >= due:
                if key not in result:
                    result.append(key)
                self.held[token] = (key, now + .13)
        return result

    def wait(self, now):
        return max(0, min((due - now for _, due in self.held.values()), default=.5))
