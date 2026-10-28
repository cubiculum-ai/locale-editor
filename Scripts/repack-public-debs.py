#!/usr/bin/env python3
"""Make a documentation/license packaging revision while preserving executable bytes."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('apt_repository',ROOT/'Scripts/apt-repository.py')
apt=importlib.util.module_from_spec(spec);spec.loader.exec_module(apt)

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--from-version',default='0.2.0-1')
parser.add_argument('--version',default='0.2.0-2')
args=parser.parse_args()
apt.check(apt.compare_versions(args.from_version,args.version)<0,'Packaging revision must advance')
args.output.mkdir(parents=True,exist_ok=True)
for package,arch in sorted(apt.MATRIX):
    source=args.input/f'{package}_{args.from_version}_{arch}.deb'
    destination=args.output/f'{package}_{args.version}_{arch}.deb'
    apt.check(not destination.exists(),'Refusing to replace a versioned package')
    _,fields,_=apt.package_info(source)
    apt.check(fields['Version']==args.from_version,'Input version differs')
    with tempfile.TemporaryDirectory(prefix='locale-public-package-') as temporary:
        root=Path(temporary)
        subprocess.run(['dpkg-deb','--raw-extract',str(source),str(root)],check=True)
        binary=root/'usr/bin/locale-editor';before=apt.digest(binary)
        docs=root/'usr/share/doc'/package;docs.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/'README.md',docs/'README.md')
        shutil.copyfile(ROOT/'LICENSE',docs/'copyright')
        shutil.copytree(ROOT/'ThirdParty',docs/'ThirdParty',dirs_exist_ok=True)
        control=apt.records((root/'DEBIAN/control').read_text())[0]
        control['Version']=args.version
        control['Provides']='locale-editor (= '+args.version+')'
        control['Maintainer']='rcfa <1831995+rcfa@users.noreply.github.com>'
        control['Homepage']='https://github.com/cubiculum-ai/locale-editor'
        control['Installed-Size']=str((sum(p.stat().st_size for p in (root/'usr').rglob('*') if p.is_file())+1023)//1024)
        (root/'DEBIAN/control').write_text(''.join(k+': '+v+'\n' for k,v in control.items()))
        for directory in [root,*[p for p in root.rglob('*') if p.is_dir()]]:directory.chmod(0o755)
        apt.check(apt.digest(binary)==before,'Executable bytes changed')
        subprocess.run(['dpkg-deb','--root-owner-group','--build',str(root),str(destination)],check=True)
        print(package,arch,'executable preserved',before,flush=True)
for arch in apt.ARCHITECTURES:
    paths=sorted(args.output.glob('*_'+args.version+'_'+arch+'.deb'))
    (args.output/f'SHA256SUMS-{args.version}-{arch}').write_text(''.join(apt.digest(p)+'  '+p.name+'\n' for p in paths))
