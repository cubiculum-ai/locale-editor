#!/usr/bin/env python3
"""Build and verify Locale Editor's signed, four-package GitHub Pages APT snapshots.

Production signing uses an existing protected local key. This tool never creates
keys, exports private material, installs packages, or changes system APT settings.
"""
import argparse
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime, parsedate_to_datetime
import hashlib
import io
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile

ARCHITECTURES = ('amd64', 'arm64')
PACKAGE_NAMES = ('locale-editor-gui', 'locale-editor-tui')
MATRIX = {(name, arch) for name in PACKAGE_NAMES for arch in ARCHITECTURES}
SUITE = 'stable'
PUBLIC_KEY = 'locale-editor-archive-keyring.asc'
SITE_LIMIT = 900 * 1024 * 1024


def check(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def command(args, **kwargs):
    result = subprocess.run([str(arg) for arg in args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise ValueError(f'{args[0]} failed: {result.stderr.decode(errors="replace")}')
    return result


def records(text):
    paragraphs = []
    for block in text.strip().split('\n\n'):
        fields = {}
        key = None
        for line in block.splitlines():
            if line.startswith((' ', '\t')):
                check(key is not None, 'Control continuation without a field')
                fields[key] += '\n' + line
            else:
                check(':' in line, 'Malformed control field')
                key, value = line.split(':', 1)
                check(re.fullmatch(r'[A-Za-z0-9-]+', key) and key not in fields, 'Invalid/duplicate control field')
                fields[key] = value.lstrip(' ')
        paragraphs.append(fields)
    return paragraphs


def relative_path(value):
    path = PurePosixPath(value)
    check(value and not path.is_absolute() and '..' not in path.parts and '\\' not in value,
          'Unsafe repository path')
    check(str(path) == value and re.fullmatch(r'[A-Za-z0-9._+~/-]+', value), 'Noncanonical repository path')
    return Path(*path.parts)


def regular(root, relative):
    path = Path(root)
    for part in relative_path(relative).parts:
        path = path / part
        check(not path.is_symlink(), 'Repository symlinks are not permitted')
    check(path.is_file(), 'Repository file is missing: ' + relative)
    return path


def package_info(filename):
    path = Path(filename)
    check(path.is_file() and not path.is_symlink(), 'A regular .deb file is required')
    control = None
    with path.open('rb') as stream:
        check(stream.read(8) == b'!<arch>\n', 'Invalid Debian archive')
        for _ in range(32):
            header = stream.read(60)
            if not header:
                break
            check(len(header) == 60 and header[58:] == b'`\n', 'Invalid ar header')
            name = header[:16].decode().strip().rstrip('/')
            size = int(header[48:58])
            check(0 <= size <= SITE_LIMIT, 'Invalid ar member size')
            if name.startswith('control.tar'):
                check(size <= 4 * 1024 * 1024, 'Control archive is too large')
                with tarfile.open(fileobj=io.BytesIO(stream.read(size)), mode='r|*') as archive:
                    count = total = 0
                    for entry in archive:
                        count += 1; total += entry.size
                        check(count <= 128 and total <= 4 * 1024 * 1024, 'Unbounded control archive contents')
                        if entry.name in ('control', './control'):
                            check(control is None and entry.isfile() and entry.size < 1024 * 1024,
                                  'Missing or invalid Debian control record')
                            control = archive.extractfile(entry).read().decode('utf-8')
                    check(control is not None, 'Missing Debian control record')
                break
            stream.seek(size + (size & 1), 1)
    check(control is not None, 'Missing Debian control archive')
    parsed = records(control)
    check(len(parsed) == 1, 'One binary control record is required')
    fields = parsed[0]
    name, arch, version = (fields.get(key, '') for key in ('Package', 'Architecture', 'Version'))
    check((name, arch) in MATRIX, 'Unsupported package or architecture')
    check(re.fullmatch(r'[0-9][A-Za-z0-9.+~\-]*', version), 'Unsupported Debian version (epochs are not admitted)')
    other = PACKAGE_NAMES[1] if name == PACKAGE_NAMES[0] else PACKAGE_NAMES[0]
    check(fields.get('Conflicts') == other and fields.get('Replaces') == other, 'Package variants must be mutually exclusive')
    destination = f'pool/main/l/locale-editor/{name}_{version}_{arch}.deb'
    return path, fields, destination


def compare_versions(left, right):
    """Debian upstream/revision ordering, without epochs (rejected at admission)."""
    def split(value):
        return value.rsplit('-', 1) if '-' in value else (value, '0')
    def part(a, b):
        i = j = 0
        def order(c):
            if c == '~': return -1
            if not c or c.isdigit(): return 0
            return ord(c) if c.isalpha() else ord(c) + 256
        while i < len(a) or j < len(b):
            while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
                x, y = order(a[i] if i < len(a) else ''), order(b[j] if j < len(b) else '')
                if x != y: return -1 if x < y else 1
                if i < len(a): i += 1
                if j < len(b): j += 1
            while i < len(a) and a[i] == '0': i += 1
            while j < len(b) and b[j] == '0': j += 1
            start_i, start_j = i, j
            while i < len(a) and a[i].isdigit(): i += 1
            while j < len(b) and b[j].isdigit(): j += 1
            x, y = a[start_i:i], b[start_j:j]
            if len(x) != len(y): return -1 if len(x) < len(y) else 1
            if x != y: return -1 if x < y else 1
        return 0
    a, b = split(left), split(right)
    return part(a[0], b[0]) or part(a[1], b[1])


def matrix(rows):
    check(len(rows) == 4 and {(fields['Package'], fields['Architecture']) for _, fields, _ in rows} == MATRIX,
          'Exactly GUI and TUI packages for both amd64 and arm64 are required')
    versions = {fields['Version'] for _, fields, _ in rows}
    check(len(versions) == 1, 'All four packages must have one version')
    return next(iter(versions))


def fingerprint(value):
    check(re.fullmatch(r'[0-9A-Fa-f]{40}', value), 'A complete signing-key fingerprint is required')
    return value.upper()


def signature_status(status, trusted):
    signatures = [line.split() for line in status.decode().splitlines() if line.startswith('[GNUPG:] VALIDSIG ')]
    check(len(signatures) == 1, 'Exactly one valid signature is required')
    fields = signatures[0]
    check(fields[2] == trusted or (len(fields) > 11 and fields[11] == trusted), 'Signature uses a different key')
    check(fields[9] in ('8', '9', '10', '11'), 'Weak signature digest is not accepted')


def verify(site, public_key, trusted, gpg='gpg'):
    root = Path(site)
    trusted = fingerprint(trusted)
    check(root.is_dir() and not root.is_symlink(), 'A regular repository directory is required')
    for item in root.rglob('*'):
        check(not item.is_symlink(), 'Repository symlinks are not permitted')
    dist = root / 'dists' / SUITE
    release_path = regular(root, f'dists/{SUITE}/Release')
    inline_bytes = regular(root, f'dists/{SUITE}/InRelease').read_bytes()
    check(inline_bytes.startswith(b'-----BEGIN PGP SIGNED MESSAGE-----\n') and
          inline_bytes.rstrip().endswith(b'-----END PGP SIGNATURE-----') and
          inline_bytes.count(b'-----BEGIN PGP SIGNATURE-----') == 1,
          'Invalid inline signature envelope')
    with tempfile.TemporaryDirectory(prefix='locale-apt-verify-', dir='/tmp') as temporary:
        os.chmod(temporary, 0o700)
        base = [gpg, '--batch', '--homedir', temporary]
        command([*base, '--import', public_key])
        listing = command([*base, '--with-colons', '--fingerprint', '--list-keys']).stdout.decode()
        primary = []
        pending = False
        for line in listing.splitlines():
            fields = line.split(':')
            if fields[0] == 'pub': pending = True
            elif fields[0] == 'fpr' and pending: primary.append(fields[9]); pending = False
            elif fields[0] == 'sub': pending = False
        check(primary == [trusted], 'Public key differs from the pinned fingerprint')
        detached = command([*base, '--status-fd', '1', '--verify', dist / 'Release.gpg', release_path])
        signature_status(detached.stdout, trusted)
        inline = command([*base, '--status-fd', '2', '--decrypt', dist / 'InRelease'])
        signature_status(inline.stderr, trusted)
        check(inline.stdout == release_path.read_bytes(), 'Inline and detached metadata disagree')
    check(regular(root, PUBLIC_KEY).read_bytes() == Path(public_key).read_bytes(), 'Published public key differs from pinned source')
    fields = records(release_path.read_text())[0]
    check(fields.get('Origin') == 'Linux Locale Editor' and fields.get('Codename') == SUITE and fields.get('Suite') == SUITE,
          'Unexpected repository identity')
    check(fields.get('Architectures') == 'amd64 arm64' and fields.get('Components') == 'main' and fields.get('Acquire-By-Hash') == 'yes',
          'Unexpected repository layout')
    now = datetime.now(timezone.utc)
    issued, expires = parsedate_to_datetime(fields['Date']), parsedate_to_datetime(fields['Valid-Until'])
    check(issued <= now + timedelta(minutes=5) and now < expires <= issued + timedelta(days=90, seconds=1),
          'Expired or invalid repository validity interval')
    expected = {f'main/binary-{arch}/Packages{suffix}' for arch in ARCHITECTURES for suffix in ('', '.xz')}
    indexed = set()
    for line in fields['SHA256'].splitlines():
        if not line.strip(): continue
        sha, size, name = line.split()
        check(name not in indexed and re.fullmatch('[a-f0-9]{64}', sha), 'Duplicate or invalid signed index')
        indexed.add(name)
        path = regular(dist, name)
        check(path.stat().st_size == int(size) and digest(path) == sha, 'Index hash/size mismatch')
        check(digest(regular(path.parent, 'by-hash/SHA256/' + sha)) == sha, 'Missing or corrupt by-hash index')
    check(indexed == expected, 'Signed architecture indexes are incomplete')
    inventory = []
    for arch in ARCHITECTURES:
        directory = dist / 'main' / f'binary-{arch}'
        raw = (directory / 'Packages').read_bytes()
        check(lzma.decompress((directory / 'Packages.xz').read_bytes()) == raw, 'Compressed index differs')
        for entry in records(raw.decode()):
            path = regular(root, entry['Filename'])
            check(entry['Size'] == str(path.stat().st_size) and entry['SHA256'] == digest(path), 'Package hash/size mismatch')
            _, control, canonical = package_info(path)
            check(entry['Filename'] == canonical and entry['Architecture'] == arch, 'Incorrect package location or architecture')
            check(all(entry.get(key) == value for key, value in control.items()), 'Indexed control metadata differs from package')
            inventory.append({key: entry[key] for key in ('Package', 'Architecture', 'Version', 'Filename', 'SHA256')})
    versions = {row['Version'] for row in inventory}
    check(1 <= len(versions) <= 2 and len(inventory) == len(versions) * 4, 'Repository exceeds retention bounds')
    for version in versions:
        check({(row['Package'], row['Architecture']) for row in inventory if row['Version'] == version} == MATRIX,
              'Incomplete package matrix')
    size = sum(path.stat().st_size for path in root.rglob('*') if path.is_file())
    check(size < SITE_LIMIT, 'Repository exceeds Pages budget')
    return {'profile': 'locale-editor.apt.v1', 'fingerprint': trusted, 'suite': SUITE,
            'validUntil': fields['Valid-Until'], 'packages': inventory, 'bytes': size}


def build(site, packages, trusted, previous=(), gpg='gpg'):
    root = Path(site)
    check(not root.exists(), 'Build a new snapshot directory')
    trusted = fingerprint(trusted)
    current = [package_info(path) for path in packages]
    version = matrix(current)
    rows = list(current)
    if previous:
        older = [package_info(path) for path in previous]
        old_version = matrix(older)
        check(compare_versions(old_version, version) < 0, 'Previous package version must be older')
        rows += older
    check(sum(path.stat().st_size for path, _, _ in rows) + 8 * 1024 * 1024 < SITE_LIMIT, 'Packages exceed Pages budget')
    root.mkdir(parents=True)
    public = command([gpg, '--batch', '--armor', '--export', trusted]).stdout
    check(b'BEGIN PGP PUBLIC KEY BLOCK' in public, 'Signing public key is unavailable')
    (root / PUBLIC_KEY).write_bytes(public)
    for source, _, relative in rows:
        target = root / relative_path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        check(digest(source) == digest(target), 'Package changed while copying')
    dist = root / 'dists' / SUITE
    indexes = []
    for arch in ARCHITECTURES:
        directory = dist / 'main' / f'binary-{arch}'
        directory.mkdir(parents=True)
        paragraphs = []
        for source, fields, relative in sorted(rows, key=lambda row: row[2]):
            if fields['Architecture'] != arch: continue
            record = {key: value for key, value in fields.items() if key not in ('Filename', 'Size', 'SHA256', 'SHA1', 'MD5sum')}
            record.update(Filename=relative, Size=str(source.stat().st_size), SHA256=digest(source))
            paragraphs.append('\n'.join(key + ': ' + value for key, value in record.items()))
        raw = ('\n\n'.join(paragraphs) + '\n\n').encode()
        for name, data in (('Packages', raw), ('Packages.xz', lzma.compress(raw))):
            path = directory / name
            path.write_bytes(data)
            by_hash = directory / 'by-hash' / 'SHA256' / digest(path)
            by_hash.parent.mkdir(parents=True, exist_ok=True)
            by_hash.write_bytes(data)
            indexes.append(path)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    release = ['Origin: Linux Locale Editor', 'Label: Linux Locale Editor', f'Suite: {SUITE}', f'Codename: {SUITE}',
               'Architectures: amd64 arm64', 'Components: main', 'Acquire-By-Hash: yes',
               'Description: Native GTK and terminal locale editor for current Kali Linux',
               'Date: ' + format_datetime(now, usegmt=True),
               'Valid-Until: ' + format_datetime(now + timedelta(days=90), usegmt=True), 'SHA256:']
    release += [f' {digest(path)} {path.stat().st_size} {path.relative_to(dist).as_posix()}' for path in indexes]
    (dist / 'Release').write_text('\n'.join(release) + '\n')
    for option, name in (('--clearsign', 'InRelease'), ('--detach-sign', 'Release.gpg')):
        command([gpg, '--batch', '--yes', '--local-user', trusted, '--digest-algo', 'SHA256', option,
                 '--output', dist / name, dist / 'Release'])
    receipt = verify(root, root / PUBLIC_KEY, trusted, gpg)
    (root / 'repository.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('build', 'verify'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--fingerprint', required=True)
    parser.add_argument('--public-key', type=Path)
    parser.add_argument('--package', action='append', default=[])
    parser.add_argument('--previous-package', action='append', default=[])
    parser.add_argument('--gpg', default='gpg')
    args = parser.parse_args()
    result = build(args.root, args.package, args.fingerprint, args.previous_package, args.gpg) if args.action == 'build' else verify(args.root, args.public_key or args.root / PUBLIC_KEY, args.fingerprint, args.gpg)
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
