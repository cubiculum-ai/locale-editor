#!/usr/bin/env python3
"""Optional non-root Debian build aid: unpack GTK headers locally, using host runtime libraries."""
import os, pathlib, re, shlex, subprocess, sys
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/gtk-sdk').resolve()
packages = root / 'packages'; packages.mkdir(parents=True, exist_ok=True)
sdk = root / 'root'; sdk.mkdir(exist_ok=True)
queue = ['libgtk-3-dev']; seen = set()
while queue:
    package = queue.pop()
    if package in seen: continue
    seen.add(package)
    result = subprocess.check_output(['apt-cache', 'depends', '--no-recommends', '--no-suggests', '--no-conflicts', '--no-breaks', '--no-replaces', '--no-enhances', package], text=True)
    for line in result.splitlines():
        match = re.search(r'Depends: ([a-z0-9.+-]+)', line)
        if match and match[1].endswith('-dev'): queue.append(match[1])
    installed = subprocess.run(['dpkg-query', '-W', '-f=${db:Status-Status}', package], capture_output=True, text=True)
    if installed.returncode == 0 and installed.stdout == 'installed': continue
    subprocess.run(['apt-get', 'download', package], cwd=packages, check=True)
for package in packages.glob('*.deb'):
    subprocess.run(['dpkg-deb', '-x', str(package), str(sdk)], check=True)
for pc in sdk.rglob('*.pc'):
    source = pc.read_text()
    source = re.sub(r'(?m)^prefix=/usr$', 'prefix=' + str(sdk / 'usr'), source)
    # Debian's architecture paths may be literal rather than relative to prefix.
    source = re.sub(r'(?m)^(libdir|includedir)=/usr/', r'\1=' + str(sdk / 'usr') + '/', source)
    pc.write_text(source)
for link in sdk.rglob('*.so'):
    if link.is_symlink():
        host = pathlib.Path('/') / link.relative_to(sdk)
        target_name = pathlib.Path(os.readlink(link)).name
        target = host.parent / target_name
        if target.exists():
            link.unlink(); link.symlink_to(target.resolve())
paths = sorted({str(pc.parent) for pc in sdk.rglob('*.pc')})
(root / 'env.sh').write_text('export PKG_CONFIG_PATH=' + shlex.quote(':'.join(paths)) + "\n")
print('GTK headers prepared. Source ' + str(root / 'env.sh') + ' before building.')
