"""Checked Hyprland actions for native Lua and legacy dispatcher builds."""
import json
import re
import subprocess


class HyprActions:
    def __init__(self, runner=None):
        self.runner=runner or self._run
        self.lua=None

    @staticmethod
    def _run(args):
        result=subprocess.run(args,capture_output=True,text=True,timeout=3)
        text=(result.stdout+'\n'+result.stderr).strip()
        # Some hyprctl builds return zero even when the compositor rejects syntax.
        if result.returncode or re.search(r'(^|\n)\s*(error:|unknown request|unknown dispatcher|invalid dispatcher)',text,re.I):
            raise ValueError('Hyprland rejected the action: '+text[:240])
        return result.stdout.strip()

    def is_lua(self):
        if self.lua is None:
            try:
                self.lua=self.runner(['hyprctl','eval','return true']).strip()=='ok'
            except (ValueError,OSError,subprocess.SubprocessError):self.lua=False
        return self.lua

    def focus(self,address):
        if not isinstance(address,str) or not re.fullmatch(r'0x[0-9a-fA-F]+',address):
            raise ValueError('Invalid window address')
        if self.is_lua():
            # Resolve the live window inside the compositor, not a stale UI workspace.
            code=('local w=hl.get_window("address:'+address+'"); '
                  'assert(w and w.mapped,"Window is no longer available"); '
                  'if w.monitor then hl.dispatch(hl.dsp.focus({monitor=w.monitor})) end; '
                  'if w.workspace then hl.dispatch(hl.dsp.focus({workspace=w.workspace})) end; '
                  'hl.dispatch(hl.dsp.focus({window=w}))')
            self.runner(['hyprctl','eval',code])
        else:
            clients=json.loads(self.runner(['hyprctl','-j','clients']))
            window=next((w for w in clients if w.get('address')==address and w.get('mapped')),None)
            if not window:raise ValueError('Window is no longer available')
            workspace=window['workspace']
            target=str(workspace['id']) if workspace['id']>0 else workspace['name']
            self.runner(['hyprctl','dispatch','workspace',target])
            self.runner(['hyprctl','dispatch','focuswindow','address:'+address])

    def workspace(self,number):
        if type(number) is not int or not 1<=number<=2147483647:raise ValueError('Invalid workspace')
        if self.is_lua():
            self.runner(['hyprctl','eval','hl.dispatch(hl.dsp.focus({workspace="'+str(number)+'"}))'])
        else:self.runner(['hyprctl','dispatch','workspace',str(number)])
