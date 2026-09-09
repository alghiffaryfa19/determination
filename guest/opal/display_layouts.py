"""Publish the shell's resolved per-output layouts for the Lua compositor config."""
import pathlib
import re


def publish(runtime, mode, displays):
    if mode not in ('auto','desktop','phone','console') or not isinstance(displays,list) or len(displays)>32:
        raise ValueError('Invalid display layouts')
    phones=[]
    for display in displays:
        if not isinstance(display,dict): raise ValueError('Invalid display')
        name=display.get('name',''); layout=display.get('mode')
        if not isinstance(name,str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}',name) or layout not in ('desktop','phone','console'):
            raise ValueError('Invalid display')
        if layout=='phone': phones.append(name)
    path=pathlib.Path(runtime)/'opal-phone-displays'
    data='mode='+mode+'\n'+''.join(name+'\n' for name in sorted(set(phones)))
    try:
        if path.read_text()==data:return False
    except FileNotFoundError:pass
    temp=path.with_suffix('.tmp');temp.write_text(data);temp.replace(path)
    return True
