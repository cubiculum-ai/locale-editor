#!/usr/bin/env python3
"""Deploy only a release snapshot verified against the public key pinned in source."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tarfile
import tempfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('apt_repository',ROOT/'Scripts/apt-repository.py')
apt=importlib.util.module_from_spec(spec);spec.loader.exec_module(apt)


def unpack(archive_path,destination):
    total=count=0
    with tarfile.open(archive_path,mode='r|gz') as archive:
        for member in archive:
            count+=1;total+=member.size
            apt.check(count<=10000 and total<apt.SITE_LIMIT,'APT snapshot exceeds site budget')
            path=apt.relative_path(member.name)
            apt.check(path.parts[0]=='apt' and (member.isdir() or member.isfile()),'Unsafe APT snapshot member')
            target=destination/path
            if member.isdir():target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                with archive.extractfile(member) as source,target.open('xb') as output:shutil.copyfileobj(source,output)


def assemble(output,repository,tag=None):
    apt.check(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository),'Invalid repository')
    output=Path(output);apt.check(not output.exists(),'Use a new site output directory');output.mkdir(parents=True)
    for name in ('index.html',):shutil.copyfile(ROOT/'docs'/name,output/name)
    shutil.copyfile(ROOT/'LICENSE',output/'LICENSE.txt');(output/'.nojekyll').touch()
    releases=json.loads(apt.command(['gh','api',f'repos/{repository}/releases?per_page=100']).stdout)
    releases=[r for r in releases if not r['draft']]
    if tag:releases=[r for r in releases if r['tag_name']==tag]
    releases.sort(key=lambda r:r['published_at'],reverse=True)
    release=next((r for r in releases if any(a['name']=='apt-site.tar.gz' for a in r['assets'])),None)
    apt.check(release is not None,'No published signed APT snapshot exists')
    names=[a['name'] for a in release['assets']]
    apt.check(len(names)==len(set(names)) and 'SHA256SUMS' in names,'Ambiguous or incomplete release assets')
    with tempfile.TemporaryDirectory(prefix='locale-pages-') as temporary:
        temporary=Path(temporary)
        apt.command(['gh','release','download',release['tag_name'],'--repo',repository,
                     '--pattern','apt-site.tar.gz','--pattern','SHA256SUMS','--dir',temporary])
        checksums={}
        for line in (temporary/'SHA256SUMS').read_text().splitlines():
            sha,name=line.split('  ',1)
            apt.check(name not in checksums and re.fullmatch('[a-f0-9]{64}',sha),'Invalid release checksums')
            checksums[name]=sha
        archive=temporary/'apt-site.tar.gz'
        apt.check(apt.digest(archive)==checksums.get('apt-site.tar.gz'),'Release snapshot checksum mismatch')
        unpack(archive,output)
    key=ROOT/'docs/apt'/apt.PUBLIC_KEY
    fingerprint=(ROOT/'docs/apt/fingerprint.txt').read_text().strip()
    receipt=apt.verify(output/'apt',key,fingerprint)
    apt.check(sum(p.stat().st_size for p in output.rglob('*') if p.is_file())<apt.SITE_LIMIT,'Complete site is too large')
    (output/'apt/fingerprint.txt').write_text(fingerprint+'\n')
    return {'release':release['tag_name'],'verified':receipt}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository',required=True)
    parser.add_argument('--tag')
    parser.add_argument('--output',type=Path,default=Path('_site'))
    args=parser.parse_args()
    print(json.dumps(assemble(args.output,args.repository,args.tag),indent=2))
