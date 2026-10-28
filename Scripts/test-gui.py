#!/usr/bin/env python3
"""Exercise real GTK controls via AT-SPI in a private Xvfb/D-Bus session; never select real defaults."""
import ctypes, json, os, pathlib, re, subprocess, sys, tempfile, time
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi
assert os.environ.get('LOCALE_EDITOR_GUI_TEST_SESSION')=='1', 'Use Scripts/check-gui.sh to create an isolated desktop session'
Atspi.init()
binary = str(pathlib.Path(sys.argv[1]).resolve())
capture_dir = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
if capture_dir: capture_dir.mkdir(parents=True, exist_ok=True)

def walk(node):
    yield node
    try:
        for index in range(node.get_child_count()):
            child = node.get_child_at_index(index)
            if child: yield from walk(child)
    except Exception: return

def name(node):
    try: return node.get_name() or ''
    except Exception: return ''

def role(node):
    try: return node.get_role_name()
    except Exception: return ''

def text(node):
    try:
        iface = node.get_text_iface()
        return Atspi.Text.get_text(iface, 0, -1) if iface else ''
    except Exception: return ''

def until(predicate, timeout=40):
    deadline = time.monotonic() + max(timeout, float(os.environ.get("LOCALE_EDITOR_TEST_TIMEOUT", "0")))
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value: return value
        except Exception: pass
        if process.poll() is not None: raise AssertionError('GUI exited: ' + str(process.returncode))
        time.sleep(.15)
    raise AssertionError('Timed out. Windows/controls: ' + repr([(role(n), name(n), text(n)[:100]) for n in list(walk(app))[:100]]))

def find(label, wanted_role=None, within=None):
    return until(lambda: next((n for n in walk(within or app) if name(n) == label and (wanted_role is None or role(n) == wanted_role)), None))

def click_node(node):
    iface=node.get_action_iface()
    assert iface and Atspi.Action.do_action(iface, 0), ('Cannot activate', role(node), name(node))
    time.sleep(.05)

def click(label, wanted_role='button', within=None): click_node(find(label, wanted_role, within))
def dialog(title): return find(title, 'dialog')
def ready():
    stable = [None]
    def check():
        nodes=list(walk(app))
        complete=any(name(n).startswith('Examples verified by glibc') for n in nodes) and not any(role(n)=='dialog' for n in nodes)
        if not complete: stable[0]=None;return False
        if stable[0] is None: stable[0]=time.monotonic()
        return time.monotonic()-stable[0]>.4
    return until(check)
def main_window(): return until(lambda: next((n for n in walk(app) if role(n)=='frame' and name(n).endswith('Linux Locale Editor')), None))
def table(within, label=None): return until(lambda: next((n for n in walk(within) if role(n)=='table' and (label is None or name(n)==label)),None))
def rows(widget):
    iface=widget.get_table_iface()
    return [[name(Atspi.Table.get_accessible_at(iface,r,c)) for c in range(Atspi.Table.get_n_columns(iface))] for r in range(Atspi.Table.get_n_rows(iface))]
def select_row(widget, index):
    iface=widget.get_table_iface()
    if not Atspi.Table.is_row_selected(iface,index): Atspi.Table.add_row_selection(iface,index)
    until(lambda:Atspi.Table.is_row_selected(iface,index))
def select_label(widget, value):
    data=rows(widget); index=next(i for i,row in enumerate(data) if row[0]==value)
    select_row(widget,index)
def section(value):
    select_label(table(main_window(),'Locale sections'),value)
    find(value,'label',main_window())
def field(value): select_label(table(main_window(),'Locale fields'),value)
def edit_entry(window, value):
    entry=until(lambda: next((n for n in walk(window) if n.get_editable_text_iface() and n.get_state_set().contains(Atspi.StateType.SHOWING)),None))
    assert Atspi.EditableText.set_text_contents(entry.get_editable_text_iface(),value)
    return entry

def key(keys, focus_main=False):
    if focus_main:
        Atspi.Component.grab_focus(table(main_window(),'Locale fields').get_component_iface())
        windows=subprocess.check_output(['xdotool','search','--onlyvisible','--pid',str(process.pid),'--name','Linux Locale Editor'],text=True).split()
        subprocess.run(['xdotool','windowactivate','--sync',windows[0]],check=True)
    if re.fullmatch(r'F[0-9]+',keys):
        # Some xdotool/XKB versions synthesize Alt with F4. Use the actual keycode.
        mapping=subprocess.check_output(['xmodmap','-pke'],text=True)
        match=re.search(r'^keycode\s+(\d+) = '+re.escape(keys)+r'\b',mapping,re.M)
        assert match, 'Function key is absent from the test display keymap'
        code=int(match[1])
        x11=ctypes.CDLL('libX11.so.6');xtst=ctypes.CDLL('libXtst.so.6')
        x11.XOpenDisplay.argtypes=[ctypes.c_char_p];x11.XOpenDisplay.restype=ctypes.c_void_p
        x11.XSync.argtypes=[ctypes.c_void_p,ctypes.c_int]
        x11.XCloseDisplay.argtypes=[ctypes.c_void_p]
        xtst.XTestFakeKeyEvent.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong]
        display=x11.XOpenDisplay(None);assert display
        try:
            assert xtst.XTestFakeKeyEvent(display,code,1,0)
            assert xtst.XTestFakeKeyEvent(display,code,0,0)
            x11.XSync(display,0)
        finally:x11.XCloseDisplay(display)
    else:
        subprocess.run(['xdotool','key','--clearmodifiers',keys],check=True)

def menu(item, heading='File'):
    click(heading,'menu',main_window());click(item,'menu item',main_window())
def custom(label, value):
    print('GUI: custom ' + label,flush=True)
    field(label);click('Custom…',within=main_window());d=dialog('Custom: '+label);edit_entry(d,value);click('Apply',within=d);ready()
def file_path(title,path,accept='Save'):
    print('GUI: ' + title,flush=True)
    d=until(lambda: next((n for n in walk(app) if role(n) in ('dialog','file chooser') and name(n)==title),None))
    if accept=='Save':
        # Native GTK save dialogs expose the filename entry through its Name label.
        entries=[n for n in walk(d) if n.get_editable_text_iface() and n.get_state_set().contains(Atspi.StateType.SHOWING)]
        entry=next((n for n in entries if name(n) in ('Name','Name:')),entries[0])
        Atspi.EditableText.set_text_contents(entry.get_editable_text_iface(),str(path))
    else:
        key('ctrl+l')
        edit_entry(d,str(path))
    click(accept,within=d)
def capture(filename):
    if capture_dir: subprocess.run(['import','-window','root',str(capture_dir/filename)],check=True)

with tempfile.TemporaryDirectory(prefix='locale-gtk-test-') as temporary:
    root=pathlib.Path(temporary)
    env={**os.environ,'NO_AT_BRIDGE':'0','GSETTINGS_BACKEND':'memory','GTK_USE_PORTAL':'0','GIO_USE_VFS':'local','GIO_USE_VOLUME_MONITOR':'unix','XDG_CONFIG_HOME':str(root/'config'),'XDG_DATA_HOME':str(root/'data')}
    log=open(root/'gui.log','w')
    wm=subprocess.Popen(['xfwm4','--compositor=off'],stdout=log,stderr=log,env=env)
    time.sleep(.3)
    process=subprocess.Popen([binary,'--gui','--base','en_US','--name','en_US.UTF-8@gtk_test'],stdout=log,stderr=log,env=env)
    app=None
    try:
        app=until(lambda:next((n for n in walk(Atspi.get_desktop(0)) if role(n)=='application' and n.get_process_id()==process.pid),None))
        ready();main_window();capture('main.png')
        click('Presets…',within=main_window());d=dialog('Date format')
        data=rows(table(d));assert '%Y-%m-%d' in data[0][0] and data[0][1]=='2026-10-27',data[:2]
        capture('date-presets.png');click('Apply',within=d);ready()
        section('Currency');field('Currency symbol');click('Presets…',within=main_window());d=dialog('Currency symbol')
        edit_entry(d,'EURO SIGN');until(lambda:len(rows(table(d)))==1);select_row(table(d),0);click('Apply',within=d);ready()
        custom('Negative: sign position','4')
        section('Names');custom('Name format','%f, %g%t%m')
        section('Yes / no responses');custom('Yes expression','^([yY]es|[jJ]a)$')
        section('Address');custom('Postal address format','%n%N%s %h%N%z %T%N%c')
        section('Character handling');field('Test characters');click('Custom…',within=main_window());d=dialog('Test characters');edit_entry(d,'äI0!');click('Apply',within=d);ready()
        until(lambda:any('U+0030' in text(n) for n in walk(main_window())));capture('characters.png')
        menu('International conventions…','Edit');d=dialog('Apply international conventions');click('Apply',within=d);ready()
        key('ctrl+z',True);ready();key('ctrl+shift+z',True);ready()
        section('Currency');capture('currency.png')
        key('ctrl+s',True);saved=root/'gtk-project.json';file_path('Save locale project',saved)
        until(saved.exists)
        data=json.loads(saved.read_text())['sections']
        assert data['LC_MONETARY']['overrides']['mon_thousands_sep']=={'text':{'_0':'\u202f'}}
        assert data['LC_MONETARY']['overrides']['mon_grouping']=={'integers':{'_0':[3,3]}}
        assert data['LC_MONETARY']['overrides']['n_sign_posn']=={'integer':{'_0':4}}
        assert data['LC_NAME']['overrides']['name_fmt']=={'text':{'_0':'%f, %g%t%m'}}
        assert data['LC_MESSAGES']['overrides']['yesexpr']=={'text':{'_0':'^([yY]es|[jJ]a)$'}}
        menu('Export locale source…');exported=root/'gtk.src';file_path('Export localedef source',exported);until(exported.exists)
        assert 'mon_thousands_sep "<U202F>"' in exported.read_text()
        compiled=root/'compiled';compiled.mkdir()
        menu('Compile to directory…');file_path('Choose compiled locale output directory',compiled,'Choose')
        d=dialog('Locale compiled');assert (compiled/'en_US.UTF-8@gtk_test/LC_MONETARY').exists();click('Close',within=d)
        menu('Install and select…');d=dialog('Install locale · scope');click('Apply',within=d)
        d=dialog('Install locale · activation');select_label(table(d),'Install only');click('Apply',within=d)
        d=dialog('Review locale installation');capture('installation.png');click('Install',within=d)
        d=dialog('Locale installation complete');assert (root/'data/linux-locale-editor/locales/en_US.UTF-8@gtk_test/LC_NAME').exists();click('Close',within=d)
        assert not (root/'config/linux-locale-editor/activate.sh').exists()
        # System scope is available; cancel before requesting authorization or changing the host.
        menu('Install and select…');d=dialog('Install locale · scope');select_label(table(d),'System-wide');click('Apply',within=d)
        d=dialog('Install locale · activation');click('Cancel',within=d)
        # Native keyboard navigation opens Custom; cancellation leaves the project intact.
        field('Currency symbol');key('F4',True);d=dialog('Custom: Currency symbol');click('Cancel',within=d)
        menu('Rename locale…','Edit');d=dialog('Rename locale');edit_entry(d,'en_US.UTF-8@gtk_unsaved');click('Apply',within=d);ready()
        key('ctrl+q',True);d=dialog('Unsaved changes');click('Cancel',within=d)
        assert process.poll() is None
        key('ctrl+q',True);d=dialog('Unsaved changes');click('Discard changes',within=d)
        assert process.wait(timeout=10)==0
    except Exception:
        capture('failure.png');log.flush();print((root/'gui.log').read_text(),file=sys.stderr);raise
    finally:
        if process.poll() is None: process.terminate();process.wait(timeout=5)
        wm.terminate();wm.wait(timeout=5)
        log.close()
print('GTK integration passed: native presets/custom fields, previews, undo/redo, file dialogs, export/compile, isolated installation, system-scope cancellation and unsaved-change protection.')
