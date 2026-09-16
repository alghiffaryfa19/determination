#!/usr/bin/env python3
"""Opal's optional Linux adapters. JSON-lines only; no shell-evaluated user input."""
import sys, os, json, subprocess, threading, time, pathlib, shutil, glob, select, struct, math, ast, operator, re
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from wallpaper_service import DEFAULTS as WALLPAPER_DEFAULTS, local_image, generate, valid_preference, image_library, browse_images
HOME = pathlib.Path.home()
STORE = HOME / '.local/state/aurora-opal/preferences.json'
lock = threading.Lock()
prefs_lock = threading.Lock()
system_osk = None
def emit(data):
    with lock:
        print(json.dumps(data), flush=True)
@lru_cache(maxsize=64)
def command_available(name):
    return bool(shutil.which(name))

def run(*args, timeout=1.4):
    if not command_available(args[0]): return ''
    try: return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=timeout).decode().strip()
    except (OSError, subprocess.SubprocessError): return ''
def spawn(args):
    try: subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError: emit({'event':'message', 'text':f'{args[0]} is not installed'})
def load():
    base = {'mode':'auto', 'palette':0, 'light':False, 'dnd':False, 'glass':0.78, 'favorites':[], 'recent':[], 'wallpaper':0, 'pinsConfigured':False, 'taskbarAutoHide':False, 'taskbarLabels':True, 'phoneButtons':False, 'controllerLayout':'standard'}
    base['displayModes'] = {}
    base['phoneDisplay'] = ''
    base['taskbarOrder'] = []
    base['reduceMotion'] = False
    base.update(WALLPAPER_DEFAULTS)
    try: base.update(json.loads(STORE.read_text()))
    except (OSError, ValueError): pass
    return base
prefs = load()
def save():
    STORE.parent.mkdir(parents=True, exist_ok=True)
    temp = STORE.with_suffix('.tmp')
    temp.write_text(json.dumps(prefs, indent=2))
    temp.replace(STORE)
    emit({'event':'preferences', 'data':prefs.copy()})
    if system_osk: system_osk.refresh(prefs)

class SystemOsk:
    def __init__(self):
        self.process = None
        self.generation = 0
        self.signature = ''
        self.lock = threading.Lock()

    def theme_signature(self, values):
        subset={key:values.get(key) for key in ('light','palette','dynamicColors','dynamicPalette','colorScheme')}
        return json.dumps(subset, sort_keys=True, separators=(',',':'))

    def publish(self, available, running, detail='', visible=False):
        emit({'event':'systemOsk','available':bool(available),'running':bool(running),'visible':bool(visible),'detail':detail})

    def visible(self):
        commands=[]
        if command_available('gdbus'):
            commands.append(['gdbus','call','--session','--dest','sm.puri.OSK0','--object-path','/sm/puri/OSK0','--method','org.freedesktop.DBus.Properties.Get','sm.puri.OSK0','Visible'])
        if command_available('busctl'):
            commands.append(['busctl','--user','get-property','sm.puri.OSK0','/sm/puri/OSK0','sm.puri.OSK0','Visible'])
        for command in commands:
            try:
                reply=subprocess.check_output(command,stderr=subprocess.DEVNULL,timeout=.8,text=True).strip().lower()
            except (OSError,subprocess.SubprocessError):
                continue
            if 'true' in reply:return True
            if 'false' in reply:return False
        return None

    def wait_ready(self, process, generation):
        for _ in range(40):
            with self.lock:
                if generation!=self.generation or process is not self.process:return
            if process.poll() is not None:return
            visible=self.visible()
            if visible is not None:
                self.publish(True,True,'Wayland input method',visible)
                return
            time.sleep(.1)
        self.publish(True,False,'Squeekboard did not register its session D-Bus service')

    def set_visible(self, visible):
        if not self.process or self.process.poll() is not None:
            self.start()
        deadline=time.monotonic()+2.5
        while time.monotonic()<deadline:
            if self.visible() is not None:break
            time.sleep(.05)
        commands=[]
        value='true' if visible else 'false'
        if command_available('gdbus'):
            commands.append(['gdbus','call','--session','--dest','sm.puri.OSK0','--object-path','/sm/puri/OSK0','--method','sm.puri.OSK0.SetVisible',value])
        if command_available('busctl'):
            commands.append(['busctl','--user','call','sm.puri.OSK0','/sm/puri/OSK0','sm.puri.OSK0','SetVisible','b',value])
        for command in commands:
            try:
                subprocess.run(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=1,check=True)
                self.publish(True,True,'Wayland input method',visible)
                return True
            except (OSError,subprocess.SubprocessError):
                continue
        self.publish(bool(shutil.which('squeekboard')),False,'System keyboard control is unavailable')
        return False

    def toggle(self):
        visible=self.visible()
        return self.set_visible(not bool(visible))

    def start(self):
        if os.environ.get('OPAL_SYSTEM_OSK','1') in ('0','false','no'):
            self.publish(False,False,'System keyboard disabled by OPAL_SYSTEM_OSK')
            return
        executable=shutil.which('squeekboard')
        if not executable:
            self.publish(False,False,'Squeekboard is not installed')
            return
        launcher=pathlib.Path(__file__).with_name('osk_theme.py')
        if not launcher.is_file():
            self.publish(False,False,'Opal keyboard theme launcher is missing')
            return
        with self.lock:
            if self.process and self.process.poll() is None: return
            self.generation+=1
            generation=self.generation
            try:
                self.process=subprocess.Popen([sys.executable,str(launcher),'--preferences',str(STORE),'--',executable],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
            except OSError as error:
                self.process=None
                self.publish(True,False,str(error))
                return
            process=self.process
            self.signature=self.theme_signature(prefs)
        self.publish(True,False,'Starting Wayland input method')
        threading.Thread(target=self.wait_ready,args=(process,generation),daemon=True).start()
        threading.Thread(target=self.watch,args=(process,generation),daemon=True).start()

    def watch(self, process, generation):
        code=process.wait()
        with self.lock:
            if generation!=self.generation or process is not self.process: return
            self.process=None
        detail='Squeekboard exited' if code==0 else f'Squeekboard exited with status {code}'
        self.publish(True,False,detail)

    def stop(self):
        with self.lock:
            self.generation+=1
            process=self.process
            self.process=None
        if not process or process.poll() is not None: return
        process.terminate()
        try: process.wait(timeout=1.5)
        except subprocess.TimeoutExpired:
            process.kill()
            try: process.wait(timeout=.5)
            except subprocess.TimeoutExpired: pass

    def restart(self):
        self.stop()
        self.start()

    def refresh(self, values):
        signature=self.theme_signature(values)
        if signature==self.signature: return
        self.signature=signature
        with self.lock: running=bool(self.process and self.process.poll() is None)
        if running: threading.Thread(target=self.restart,daemon=True).start()

def settings(which):
    choices = {
        'network': [['nm-connection-editor'], ['systemsettings','kcm_networkmanagement'], ['kitty','-e','nmtui']],
        'bluetooth': [['blueman-manager'], ['systemsettings','kcm_bluetooth']],
        'audio': [['pavucontrol'], ['systemsettings','kcm_pulseaudio']],
        'display': [['systemsettings','kcm_kscreen']],
        'files': [['xdg-open',str(HOME)]],
        'terminal': [['kitty'], ['foot'], ['alacritty']],
        'browser': [['xdg-open','https://www.google.com']],
        'steam': [['steam','-gamepadui']],
        'lock': [['hyprlock'], ['loginctl','lock-session']],
    }
    for cmd in choices.get(which, []):
        if shutil.which(cmd[0]): spawn(cmd); return
    emit({'event':'message','text':'No compatible application installed'})

def calculate(expr):
    # Deliberately tiny calculator, never Python eval or shell execution.
    ops = {ast.Add:operator.add, ast.Sub:operator.sub, ast.Mult:operator.mul, ast.Div:operator.truediv, ast.Mod:operator.mod, ast.Pow:operator.pow}
    def visit(n):
        if isinstance(n,ast.Constant) and type(n.value) in (int,float): return n.value
        if isinstance(n,ast.UnaryOp) and isinstance(n.op,(ast.UAdd,ast.USub)): return visit(n.operand) * (-1 if isinstance(n.op,ast.USub) else 1)
        if isinstance(n,ast.BinOp) and type(n.op) in ops:
            a,b=visit(n.left),visit(n.right)
            if abs(a)>1e15 or abs(b)>1e15 or isinstance(n.op,ast.Pow) and abs(b)>12: raise ValueError()
            return ops[type(n.op)](a,b)
        raise ValueError()
    try:
        if len(expr)>100: raise ValueError()
        value=visit(ast.parse(expr,mode='eval').body)
        if isinstance(value,complex) or not math.isfinite(value) or abs(value)>1e18: raise ValueError()
        return format(value,'.12g')
    except Exception: return ''

from clipboard_service import ClipboardHistory
clipboard = ClipboardHistory(emit)
from connectivity import Connectivity
connectivity = Connectivity(emit)
from hypr_actions import HyprActions
hypr_actions = HyprActions()


def publish_wallpapers(c):
    try:
        if c.get('browse'):
            data=browse_images(c.get('folder',''))
        else:
            data={'items':image_library(c.get('folder',''), prefs.get('wallpaperPath','')), 'folders':[], 'folder':'', 'parent':''}
        emit({'event':'wallpapers','request':c.get('request'), **data, 'error':''})
    except (ValueError, OSError) as error:
        emit({'event':'wallpapers','request':c.get('request'), 'items':[], 'error':str(error)})


def commands():
    for line in sys.stdin:
        try:
            c=json.loads(line); action=c.get('action')
            if action=='preference':
                key=c.get('key'); value=c.get('value')
                valid = key=='controllerLayout' and value in ('standard','nintendo') or key=='mode' and value in ('auto','desktop','phone','console') or key in ('palette','wallpaper') and type(value)==int and 0<=value<=3 or key in ('light','dnd','taskbarAutoHide','taskbarLabels','phoneButtons','reduceMotion') and type(value)==bool or key=='glass' and type(value) in (int,float) and .45<=value<=1
                valid = valid or valid_preference(key, value)
                valid = valid or key=='taskbarOrder' and isinstance(value,list) and len(value)<=128 and all(isinstance(v,str) and 0<len(v)<300 for v in value) and len(set(value))==len(value)
                valid = valid or key=='phoneDisplay' and isinstance(value,str) and 0<len(value)<=128 and all(ch.isalnum() or ch in '_.:-' for ch in value)
                valid = valid or key=='displayModes' and isinstance(value,dict) and len(value)<=32 and all(isinstance(k,str) and 0<len(k)<=200 and v in ('desktop','phone') for k,v in value.items())
                if valid:
                    with prefs_lock: prefs[key]=value; save()
            elif action=='display-layouts':
                from display_layouts import publish
                runtime=os.environ.get('XDG_RUNTIME_DIR')
                if runtime and publish(runtime,c.get('mode'),c.get('displays')) and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') and shutil.which('hyprctl'):
                    subprocess.run(['hyprctl','reload','config-only'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
            elif action=='wallpaper-list':
                threading.Thread(target=publish_wallpapers,args=(c,),daemon=True).start()
            elif action=='wallpaper':
                try:
                    path = local_image(c.get('path')) if c.get('path') else None
                    extra={}
                    for key in ('wallpaperFit','wallpaperDim','wallpaper'):
                        if key not in c: continue
                        value=c[key]
                        if not (type(value) is int and 0<=value<=3 if key=='wallpaper' else valid_preference(key,value)):
                            raise ValueError('Invalid wallpaper preview settings.')
                        extra[key]=value
                    with prefs_lock:
                        prefs.update(extra)
                        prefs['wallpaperPath'] = path.as_uri() if path else ''
                        save()
                    emit({'event':'message','text':'Wallpaper updated' if path else 'Built-in wallpaper restored'})
                except (ValueError, OSError) as error:
                    emit({'event':'message','text':str(error)})
            elif action=='matugen':
                emit({'event':'themeBusy','busy':True})
                try:
                    path = local_image(prefs.get('wallpaperPath'))
                    palette = generate(path, prefs.get('colorScheme','scheme-tonal-spot'))
                    with prefs_lock:
                        prefs['dynamicPalette'] = palette
                        prefs['dynamicColors'] = True
                        save()
                    emit({'event':'message','text':'Wallpaper colors applied · light and dark palettes ready'})
                except Exception as error:
                    emit({'event':'message','text':str(error) if isinstance(error, ValueError) else 'Matugen could not read this image or generate colors. Previous colors kept.'})
                finally:
                    emit({'event':'themeBusy','busy':False})
            elif action in ('pin','recent'):
                app=c.get('id','')
                if isinstance(app,str) and 0<len(app)<300:
                    with prefs_lock:
                        key='favorites' if action=='pin' else 'recent'
                        items=list(prefs[key])
                        if action=='pin' and not prefs.get('pinsConfigured'):
                            defaults=c.get('initial',[])
                            if isinstance(defaults,list): items=[i for i in defaults[:24] if isinstance(i,str) and len(i)<300]
                            prefs['pinsConfigured']=True
                        if app in items: items.remove(app)
                        elif action=='pin': items.append(app)
                        if action=='recent': items.insert(0,app)
                        prefs[key]=items[:24]; save()
            elif action in ('focus-window','workspace'):
                try:
                    if action=='focus-window':hypr_actions.focus(c.get('address'))
                    else:hypr_actions.workspace(c.get('number'))
                except (ValueError,OSError,subprocess.SubprocessError) as error:
                    emit({'event':'message','text':str(error)})
            elif action=='connectivity': connectivity.request(c)
            elif action=='settings': settings(c.get('which'))
            elif action=='system-osk' and c.get('verb') in ('show','hide','toggle'):
                if not system_osk:
                    emit({'event':'systemOsk','available':False,'running':False,'visible':False,'detail':'System keyboard is not initialized'})
                elif c.get('verb')=='toggle': system_osk.toggle()
                else: system_osk.set_visible(c.get('verb')=='show')
            elif action=='volume': run('wpctl','set-volume','-l','1','@DEFAULT_AUDIO_SINK@',str(max(0,min(100,int(c['value']))))+'%')
            elif action=='mute': run('wpctl','set-mute','@DEFAULT_AUDIO_SINK@','toggle')
            elif action=='mic': run('wpctl','set-mute','@DEFAULT_AUDIO_SOURCE@','toggle')
            elif action=='brightness': run('brightnessctl','set',str(max(1,min(100,int(c['value']))))+'%')
            elif action=='wifi': run('nmcli','radio','wifi','off' if c.get('enabled') else 'on')
            elif action=='bluetooth': run('bluetoothctl','power','off' if c.get('enabled') else 'on')
            elif action=='media' and c.get('verb') in ('play-pause','next','previous'):
                if command_available('playerctl'): run('playerctl',c['verb'])
                else: run('aurora-media-action',c['verb'])
            elif action=='profile' and c.get('value') in ('power-saver','balanced','performance'): run('powerprofilesctl','set',c['value'])
            elif action=='screenshot':
                time.sleep(.5)
                folder=HOME/'Pictures/Screenshots'; folder.mkdir(parents=True,exist_ok=True)
                dest=str(folder/time.strftime('Opal-%Y%m%d-%H%M%S.png'))
                if shutil.which('grim'):
                    try:
                        subprocess.run(['grim',dest],check=True,timeout=5)
                        emit({'event':'message','text':'Screenshot saved to Pictures/Screenshots'})
                    except Exception: emit({'event':'message','text':'Screenshot failed'})
            elif action=='power' and c.get('verb')=='suspend':
                emit({'event':'message','text':'Suspend is unavailable while Android owns the power lifecycle'})
            elif action=='power' and c.get('verb') in ('reboot','poweroff'):
                spawn(['aurora-signal',c['verb']])
            elif action=='power' and c.get('verb')=='logout':
                pathlib.Path('/mnt/aurora-control/exit').touch()
            elif action=='calculate': emit({'event':'calculation','query':c.get('text',''),'result':calculate(c.get('text',''))})
            elif action=='clipboard':
                if shutil.which('wl-copy'): subprocess.run(['wl-copy'],input=str(c.get('text','')).encode('utf-8'),timeout=2)
            elif action=='clipboard-list': clipboard.publish()
            elif action=='clipboard-copy': clipboard.copy(c.get('id',''))
            elif action=='clipboard-delete': clipboard.delete(c.get('id',''))
            elif action=='clipboard-clear': clipboard.clear()
            elif action=='clipboard-pause' and type(c.get('paused')) is bool: clipboard.set_paused(c['paused'])
            elif action=='web': spawn(['xdg-open','https://www.google.com/search?q='+__import__('urllib.parse',fromlist=['quote']).quote(str(c.get('text','')))])
        except Exception as e: emit({'event':'message','text':'That action could not be completed'})

last_cpu=None
status_workers=ThreadPoolExecutor(max_workers=8, thread_name_prefix='opal-status')
status_cache={}
status_cache_lock=threading.Lock()

def status_probe(specs):
    futures={}
    values={}
    now=time.monotonic()
    with status_cache_lock:
        for key,args,ttl in specs:
            cached=status_cache.get(key)
            if ttl and cached and now-cached[0] < ttl:
                values[key]=cached[1]
            else:
                futures[key]=status_workers.submit(run,*args)
    for key,future in futures.items():
        try: value=future.result()
        except Exception: value=''
        values[key]=value
        for spec_key,_,ttl in specs:
            if spec_key==key and ttl:
                with status_cache_lock: status_cache[key]=(time.monotonic(),value)
                break
    return values

def status():
    global last_cpu
    # Compositor fields arrive independently from hypr_events, never from this poll.
    s={'volume':0,'muted':False,'network':'Offline','wifi':False,'bluetooth':False,'track':'','artist':'','art':'','playing':False,'battery':-1,'charging':False,'brightness':-1,'cpu':0,'memory':0,'profile':'','uptime':''}
    values=status_probe([
        ('volume',('wpctl','get-volume','@DEFAULT_AUDIO_SINK@'),0),
        ('audioOutput',('wpctl','inspect','@DEFAULT_AUDIO_SINK@'),10),
        ('mic',('wpctl','get-volume','@DEFAULT_AUDIO_SOURCE@'),0),
        ('network',('nmcli','-t','-f','NAME,TYPE','connection','show','--active'),3),
        ('wifi',('nmcli','radio','wifi'),3),
        ('bluetooth',('bluetoothctl','show'),5),
        ('media',('playerctl','metadata','--format','{{title}}\n{{artist}}\n{{mpris:artUrl}}\n{{status}}'),0),
        ('profile',('powerprofilesctl','get'),10),
    ])
    v=values['volume']
    try: s['volume']=round(float(v.split()[1])*100)
    except (ValueError,IndexError): pass
    s['muted']='MUTED' in v
    description=re.search(r'node\.description\s*=\s*"([^"]+)"',values['audioOutput'])
    s['audioOutput']=description.group(1) if description else ''
    s['micMuted']='MUTED' in values['mic']
    n=values['network']
    s['network']=next((l.rsplit(':',1)[0] for l in n.splitlines() if not l.endswith(':loopback')),'Offline')
    s['wifi']=values['wifi']=='enabled'
    s['bluetooth']='Powered: yes' in values['bluetooth']
    meta=values['media'].splitlines()
    if meta:
        for i,k in enumerate(('track','artist','art')):
            if len(meta)>i: s[k]=meta[i]
        s['playing']=len(meta)>3 and meta[3]=='Playing'
    for b in ['/sys/class/power_supply/bms/capacity', *glob.glob('/sys/class/power_supply/BAT*/capacity')]:
        try:
            s['battery']=int(pathlib.Path(b).read_text()); s['charging']=pathlib.Path(b).with_name('status').read_text().strip()=='Charging'
        except (OSError,ValueError): pass
    for b in glob.glob('/sys/class/backlight/*'):
        try: s['brightness']=round(int(pathlib.Path(b,'brightness').read_text())/int(pathlib.Path(b,'max_brightness').read_text())*100)
        except (OSError,ValueError,ZeroDivisionError): pass
    try:
        cpu=list(map(int,pathlib.Path('/proc/stat').read_text().splitlines()[0].split()[1:8])); total=sum(cpu); idle=cpu[3]+cpu[4]
        if last_cpu and total>last_cpu[0]: s['cpu']=round(100*(1-(idle-last_cpu[1])/(total-last_cpu[0])))
        last_cpu=(total,idle)
        mem={l.split(':')[0]:int(l.split()[1]) for l in pathlib.Path('/proc/meminfo').read_text().splitlines()}
        s['memory']=round(100*(1-mem['MemAvailable']/mem['MemTotal']))
        hrs=int(float(pathlib.Path('/proc/uptime').read_text().split()[0]))//3600
        s['uptime']=str(hrs)+'h'
    except (OSError,ValueError,KeyError): pass
    s['profile']=values['profile']
    return s

def library_art():
    """Index Steam's existing local artwork; never download library assets."""
    result={}
    bases=[HOME/'.local/share/Steam/appcache/librarycache', HOME/'.steam/steam/appcache/librarycache']
    seen=set()
    for base in bases:
        try:
            resolved=base.resolve()
            if resolved in seen or not base.is_dir(): continue
            seen.add(resolved)
            for pattern in ('*/*','*/*/*','*'):
                for path in base.glob(pattern):
                    if not path.is_file(): continue
                    relative=path.relative_to(base)
                    appid=relative.parts[0] if len(relative.parts)>1 else path.name.split('_',1)[0]
                    if not appid.isdigit(): continue
                    name=path.stem.lower()
                    kind='cover' if '600x900' in name or 'library_capsule' in name else 'hero' if 'library_hero' in name and 'blur' not in name else 'header' if 'library_header' in name else None
                    if kind: result.setdefault(appid,{})[kind]=path.resolve().as_uri()
        except OSError: continue
    return result

def controllers():
    from controller_mapping import device_maps, button_action, axis_orientation
    # Linux joystick API, read-only. Never grabs devices or injects global input.
    while True:
        paths=glob.glob('/dev/input/js*')
        f=None
        name=''
        for p in paths:
            candidate=None
            try:
                import fcntl
                candidate=open(p,'rb',buffering=0)
                buf=bytearray(128)
                fcntl.ioctl(candidate.fileno(), 0x80000000 | (128<<16) | (ord('j')<<8) | 0x13, buf)
                candidate_name=bytes(buf).split(b'\0',1)[0].decode(errors='replace')
                buttons=bytearray(1)
                fcntl.ioctl(candidate.fileno(), 0x80016a12, buttons)
                # Absolute pointer devices can expose js nodes too; they are not gamepads.
                if buttons[0]<6 or any(word in candidate_name.lower() for word in ('pointer','mouse','keyboard')):
                    candidate.close(); continue
                f=candidate; name=candidate_name; break
            except OSError:
                if candidate: candidate.close()
        emit({'event':'controller','connected':f is not None,'name':name})
        if f is None: time.sleep(5); continue
        try:
            button_codes,axis_codes=device_maps(f)
            previous={}
            held={}
            while True:
                now=time.monotonic()
                wait=max(0,min((due-now for _,due in held.values()),default=2))
                if not select.select([f],[],[],wait)[0]:
                    now=time.monotonic()
                    for axis,(key,due) in list(held.items()):
                        if now>=due:
                            emit({'event':'navigation','key':key})
                            held[axis]=(key,now+.13)
                    continue
                data=f.read(8)
                if len(data)!=8: break
                _,value,kind,number=struct.unpack('IhBB',data)
                if kind & 0x80: continue
                nav=None
                if kind==1 and value==1:
                    nav=button_action(number,prefs.get('controllerLayout','standard'),button_codes)
                orientation=axis_orientation(number,axis_codes) if kind==2 else None
                if orientation:
                    direction=0 if abs(value)<16000 else (1 if value>0 else -1)
                    if direction and previous.get(number)!=direction:
                        nav=('right' if direction>0 else 'left') if orientation=='horizontal' else ('down' if direction>0 else 'up')
                        held[number]=(nav,time.monotonic()+.38)
                    elif not direction: held.pop(number,None)
                    previous[number]=direction
                if nav: emit({'event':'navigation','key':nav})
        except OSError: pass
        finally: f.close()
        time.sleep(2)

def main():
    import atexit, signal
    global system_osk
    system_osk=SystemOsk()
    atexit.register(clipboard.stop)
    atexit.register(system_osk.stop)
    atexit.register(status_workers.shutdown, wait=False, cancel_futures=True)
    def shutdown(signum, frame):
        clipboard.stop()
        system_osk.stop()
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    threading.Thread(target=clipboard.watch,daemon=True).start()
    emit({'event':'preferences','data':prefs})
    system_osk.start()
    threading.Thread(target=commands,daemon=True).start()
    threading.Thread(target=controllers,daemon=True).start()
    threading.Thread(target=lambda:emit({'event':'libraryArt','data':library_art()}),daemon=True).start()
    from hypr_events import listen as listen_hyprland
    threading.Thread(target=listen_hyprland, args=(emit,), daemon=True).start()
    last_published=None
    while True:
        try:
            current=status()
            if current != last_published:
                emit({'event':'status','data':current})
                last_published=current
        except Exception: pass
        time.sleep(2)

if __name__ == '__main__':
    main()
