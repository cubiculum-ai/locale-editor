#!/usr/bin/env python3
"""Audit the Git source snapshot; private operator inputs and binaries stay local."""
import argparse
from pathlib import PurePosixPath
import re
import subprocess

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--staged',action='store_true')
args=parser.parse_args()
files=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
blocked={'.local','.apt-work','.build','dist','bin','.swiftpm','work'}
private_scripts={'Scripts/check-stash.sh','Scripts/check-kalipi.sh'}
patterns=[rb'-----BEGIN PGP PRIVATE KEY BLOCK-----',rb'gh[pousr]_[A-Za-z0-9_]{25,}',
          rb'pirate-mora\.ts\.net',rb'/Users/rcfa/',rb'/Users/Shared/Developer/',rb'/opt/locale-editor-build/']
for name in filter(None,files):
    assert PurePosixPath(name).parts[0] not in blocked and name not in private_scripts,name
    mode=subprocess.check_output(['git','ls-files','--stage','--',name]).split()[0]
    assert mode!=b'120000','Source symlink requires review: '+name
    data=subprocess.check_output(['git','show',':'+name]) if args.staged else open(name,'rb').read()
    data.decode('utf-8')  # Public source contains text/SVG only; packages live in releases.
    for pattern in patterns:
        # This audit's literal deny patterns are code, not private operator data.
        if name=='Scripts/audit-public.py':continue
        assert not re.search(pattern,data),'Private publication input in '+name
print('Public source audit passed.')
