#!/usr/bin/env python3
"""Check all four transported .debs against native checksums and their ELF architecture."""
import argparse, hashlib, io, json, tarfile
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--directory',type=Path,default=Path(__file__).resolve().parent.parent/'dist')
parser.add_argument('--package-version',default='0.2.0-2')
args=parser.parse_args();root=args.directory;manifest=[]
for path in sorted(root.glob('locale-editor-*_'+args.package_version+'_*.deb')):
    digest=hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda:handle.read(1024*1024),b''):digest.update(chunk)
        handle.seek(0);assert handle.read(8)==b'!<arch>\n'
        architecture=None;machine=None;package=None
        while True:
            header=handle.read(60)
            if not header:break
            size=int(header[48:58]);name=header[:16].decode().strip().rstrip('/')
            data=handle.read(size)
            if size%2:handle.read(1)
            if name.startswith(('control.tar','data.tar')):
                with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as archive:
                    if name.startswith('control.tar'):
                        entry=next(m for m in archive.getmembers() if m.name.lstrip('./')=='control')
                        control=archive.extractfile(entry).read().decode()
                        architecture=next(l.split(': ',1)[1] for l in control.splitlines() if l.startswith('Architecture: '))
                        package=next(l.split(': ',1)[1] for l in control.splitlines() if l.startswith('Package: '))
                    else:
                        entry=next(m for m in archive.getmembers() if m.name.lstrip('./')=='usr/bin/locale-editor')
                        assert entry.isfile()
                        elf=archive.extractfile(entry).read(20)
                        assert elf[:5]==b'\x7fELF\x02'
                        machine=int.from_bytes(elf[18:20],'little' if elf[5]==1 else 'big')
    assert machine=={'amd64':62,'arm64':183}[architecture],path.name
    expected=[]
    for checksum in root.glob('SHA256SUMS-'+args.package_version+'-*'):
        expected += [line.split()[0] for line in checksum.read_text().splitlines() if line.split()[-1].endswith(path.name)]
    assert expected and all(value==digest.hexdigest() for value in expected),path.name
    manifest.append({'file':path.name,'package':package,'architecture':architecture,'size':path.stat().st_size,'sha256':digest.hexdigest()})
assert {(item['package'],item['architecture']) for item in manifest}=={(p,a) for p in ('locale-editor-gui','locale-editor-tui') for a in ('amd64','arm64')}
assert len(manifest)==4
(root/'SHA256SUMS').write_text(''.join(item['sha256']+'  '+item['file']+'\n' for item in manifest))
(root/'packages.json').write_text(json.dumps({'version':args.package_version,'target':'Kali 2026.3 / glibc 2.43 or later','packages':manifest},indent=2)+'\n')
print('All four packages match native-build checksums and their ELF architecture labels.')
