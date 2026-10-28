#!/usr/bin/env python3
"""Validate Debian contents, dependency isolation, multicall dispatch and apt conflict resolution.
All installs are simulated. Locale compilation and extraction use temporary directories.
"""
import io, json, os, pathlib, subprocess, sys, tarfile, tempfile, xml.etree.ElementTree as ET
from tui_harness import TUI

packages = [pathlib.Path(p).resolve() for p in sys.argv[1:]]
assert len(packages)==2, 'Pass terminal and GUI .deb files'
metadata={}
def run(args, **kwargs): return subprocess.run([str(a) for a in args], text=True, capture_output=True, **kwargs)
def control(path):
    text=subprocess.check_output(['dpkg-deb','-f',str(path)],text=True)
    fields={}
    for line in text.splitlines():
        if line and not line[0].isspace():
            key,value=line.split(':',1);fields[key]=value.strip()
    return fields,text
with tempfile.TemporaryDirectory(prefix='locale-deb-check-') as temp:
    root=pathlib.Path(temp)
    for package in packages:
        info,raw=control(package);name=info['Package'];metadata[name]=(package,info,raw)
        variant=name.removeprefix('locale-editor-');assert variant in ('gui','tui')
        other='locale-editor-'+('tui' if variant=='gui' else 'gui')
        assert info['Conflicts']==other and info['Replaces']==other
        assert 'locale-editor' in info['Provides'] and 'locales' in info['Depends'] and 'pkexec' in info['Depends']
        if variant=='tui': assert not any(word in info['Depends'].lower() for word in ('gtk','gdk','qt','libx11'))
        data=subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(package)])
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for member in archive:
                assert member.uid==0 and member.gid==0
                assert member.mode & 0o6000 == 0, member.name
        install=root/variant;subprocess.run(['dpkg-deb','-x',str(package),str(install)],check=True)
        binary=install/'usr/bin/locale-editor'
        for alias in ('locale-edit','locale-editor-tui','locale-edit-tui'):
            assert (binary.parent/alias).is_symlink() and os.path.samefile(binary,binary.parent/alias)
        policy=ET.parse(install/'usr/share/polkit-1/actions/org.linuxlocaleeditor.install.policy').getroot()
        action=policy.find('action');assert action.attrib['id']=='org.linuxlocaleeditor.install'
        assert all(action.find('defaults/'+key).text=='auth_admin' for key in ('allow_any','allow_inactive','allow_active'))
        annotations={a.attrib['key']:a.text for a in action.findall('annotate')}
        assert annotations['org.freedesktop.policykit.exec.path']=='/usr/bin/locale-editor'
        assert annotations['org.freedesktop.policykit.exec.argv1']=='--install-system'
        assert 'org.freedesktop.policykit.exec.allow_gui' not in annotations
        desktop=install/'usr/share/applications/org.linuxlocaleeditor.Editor.desktop'
        assert desktop.exists()==(variant=='gui')
        if desktop.exists():subprocess.run(['desktop-file-validate',str(desktop)],check=True)
        env={k:v for k,v in os.environ.items() if k not in ('DISPLAY','WAYLAND_DISPLAY')}
        version=run([binary,'--version'],env=env,check=True).stdout
        assert ('GTK + TUI' if variant=='gui' else 'TUI only') in version
        if variant=='tui':
            result=run([binary,'--gui'],env=env);assert result.returncode!=0 and 'terminal-only' in result.stderr
        project=root/(variant+'.json')
        subprocess.run([str(binary),'new','--base','en_US','--name','en_US.UTF-8@deb_test','--output',str(project)],env=env,check=True,stdout=subprocess.DEVNULL)
        preview=run([binary,'preview','--project',project],env=env,check=True)
        assert json.loads(preview.stdout)['engine'].startswith('glibc:')
        if os.geteuid()!=0:
            denied=run([binary,'--install-system','/tmp/not-a-locale-package'],env=env)
            assert denied.returncode!=0 and 'administrator privileges' in denied.stderr
        # The GUI package's symlink must select terminal mode without --tui or a display.
        app=TUI(str(binary.parent/'locale-edit-tui'),str(root/(variant+'-config')),force_tui=False)
        try:app.ready();app.send('q');assert app.wait_exit()==0
        finally:app.close()
    gui=metadata['locale-editor-gui'];tui=metadata['locale-editor-tui']
    both=run(['apt-get','-s','-o','Debug::NoLocking=true','install',gui[0],tui[0]])
    assert both.returncode!=0 and 'Conflicts' in both.stdout+both.stderr, both.stdout+both.stderr
    original='\n\n'.join(block for block in pathlib.Path('/var/lib/dpkg/status').read_text().split('\n\n') if not block.startswith(('Package: locale-editor-gui\n','Package: locale-editor-tui\n')))
    # A private dpkg status copy lets apt demonstrate switching in both directions.
    for old,new in ((tui,gui),(gui,tui)):
        status=root/'status'
        status.write_text(original.rstrip()+'\n\n'+old[2].rstrip()+'\nStatus: install ok installed\n\n')
        result=run(['apt-get','-s','-o','Debug::NoLocking=true','-o','Dir::State::status='+str(status),'-o','APT::Install-Recommends=false','install',new[0]])
        assert result.returncode==0, result.stdout+result.stderr
        assert 'Remv '+old[1]['Package'] in result.stdout, result.stdout
        assert 'Inst '+new[1]['Package'] in result.stdout, result.stdout
print('Debian package checks passed: root-owned safe contents, isolated dependencies, native policy/desktop data, CLI workers, aliases, and apt mutual exclusion/switching. No system packages were installed.')
