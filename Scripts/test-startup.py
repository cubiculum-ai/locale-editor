#!/usr/bin/env python3
"""Regression for the arm64 exited-worker wait stall, using the actual terminal UI."""
import pathlib, subprocess, sys, tempfile, time
from tui_harness import TUI

binary=str(pathlib.Path(sys.argv[1]).resolve())
count=int(sys.argv[2]) if len(sys.argv)>2 else 8
assert 1 <= count <= 100
with tempfile.TemporaryDirectory(prefix='locale-startup-regression-') as directory:
    seed=pathlib.Path(directory)/'seed.json'
    subprocess.run([binary,'new','--base','en_US','--name','en_US.UTF-8@file_test','--output',str(seed)],check=True,stdout=subprocess.DEVNULL)
    for attempt in range(count):
        start=time.monotonic()
        app=TUI(binary,str(pathlib.Path(directory)/'config'),arguments=['--project',str(seed)])
        try:
            app.ready();app.send('q');assert app.wait_exit()==0
        finally:app.close()
        print(f'Startup {attempt+1}/{count}: {time.monotonic()-start:.2f}s',flush=True)
print('Repeated terminal startup passed: compiled previews completed and workers were reaped.')
