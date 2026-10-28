#!/usr/bin/env python3
"""Prepare signed publication assets locally; does not push, publish or install."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tarfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('apt_repository',ROOT/'Scripts/apt-repository.py')
apt=importlib.util.module_from_spec(spec);spec.loader.exec_module(apt)


def prepare(packages,output,config):
    config=Path(config)
    apt.check(config.stat().st_uid==os.getuid() and config.stat().st_mode & 0o077==0,'Signing configuration must be private and user-owned')
    settings=json.loads(config.read_text());home=Path(settings['gnupgHome']).resolve()
    apt.check(not home.is_relative_to(ROOT) and home.stat().st_uid==os.getuid() and home.stat().st_mode & 0o077==0,
              'Signing keys must stay in a protected home outside the repository')
    private=list((home/'private-keys-v1.d').glob('*.key'))
    apt.check(private and all(b'(protected-private-key' in key.read_bytes() or b'(shadowed-private-key' in key.read_bytes() for key in private),
              'Publishing requires protected private keys or hardware-backed keys')
    trusted=(ROOT/'docs/apt/fingerprint.txt').read_text().strip()
    apt.check(settings['fingerprint']==trusted,'Local signing identity differs from reviewed source')
    output=Path(output);apt.check(not output.exists(),'Use a new release staging directory');output.mkdir(parents=True,mode=0o700)
    paths=list(map(Path,packages));version=apt.matrix([apt.package_info(path) for path in paths])
    os.environ['GNUPGHOME']=str(home)
    receipt=apt.build(output/'snapshot/apt',paths,trusted)
    apt.verify(output/'snapshot/apt',ROOT/'docs/apt'/apt.PUBLIC_KEY,trusted)
    assets=output/'assets';assets.mkdir()
    for path in paths:
        _,_,relative=apt.package_info(path);shutil.copyfile(path,assets/Path(relative).name)
    with tarfile.open(assets/'apt-site.tar.gz',mode='w:gz') as archive:
        def metadata(info):
            info.uid=info.gid=0;info.uname=info.gname='';info.mode=0o755 if info.isdir() else 0o644
            return info
        archive.add(output/'snapshot/apt',arcname='apt',filter=metadata)
    files=sorted(assets.iterdir())
    (assets/'SHA256SUMS').write_text(''.join(apt.digest(path)+'  '+path.name+'\n' for path in files))
    (output/'receipt.json').write_text(json.dumps({'version':version,'repository':receipt,'assets':{p.name:apt.digest(p) for p in assets.iterdir()}},indent=2)+'\n')
    return {'version':version,'assets':str(assets),'validUntil':receipt['validUntil'],'fingerprint':trusted}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',action='append',required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--signing-config',type=Path,default=Path.home()/'.config/locale-editor-release/apt-signing.json')
    args=parser.parse_args()
    print(json.dumps(prepare(args.package,args.output,args.signing_config),indent=2))
