#!/usr/bin/env python3
"""Signed-repository tests with disposable fixture keys and isolated APT state."""
import getpass
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('apt_repository',Path(__file__).with_name('apt-repository.py'))
apt=importlib.util.module_from_spec(spec);spec.loader.exec_module(apt)


def fixture(path,name,arch,version='0.2.0-2'):
    other='locale-editor-tui' if name=='locale-editor-gui' else 'locale-editor-gui'
    control=(f'Package: {name}\nVersion: {version}\nArchitecture: {arch}\nMaintainer: Fixture <test@example.invalid>\n'
             f'Conflicts: {other}\nReplaces: {other}\nProvides: locale-editor\nDescription: Isolated test fixture\n second line\n').encode()
    members=[]
    for name_,content in [('control.tar.xz',control),('data.tar.xz',None)]:
        output=io.BytesIO()
        with tarfile.open(fileobj=output,mode='w:xz') as archive:
            if content:
                info=tarfile.TarInfo('./control');info.size=len(content);archive.addfile(info,io.BytesIO(content))
        members.append((name_,output.getvalue()))
    with path.open('wb') as out:
        out.write(b'!<arch>\n')
        for name_,data in [('debian-binary',b'2.0\n')]+members:
            out.write(f'{name_+"/":16}{0:12}{0:6}{0:6}{"100644":8}{len(data):10}`\n'.encode());out.write(data)
            if len(data)%2:out.write(b'\n')
    return path


class RepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='locale-apt-test-',dir='/tmp')
        cls.root=Path(cls.temp.name);cls.home=cls.root/'keys';cls.home.mkdir(mode=0o700)
        cls.gpg=shutil.which('gpg');assert cls.gpg
        cls.environment=patch.dict(os.environ,{'GNUPGHOME':str(cls.home)});cls.environment.start()
        # This unprotected key is disposable test data, never a publishing identity.
        apt.command([cls.gpg,'--batch','--pinentry-mode','loopback','--passphrase','','--quick-generate-key',
                     'Locale Editor disposable test key','ed25519','sign','1d'])
        listing=apt.command([cls.gpg,'--with-colons','--fingerprint','--list-keys']).stdout.decode()
        cls.fpr=next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
        cls.packages=[fixture(cls.root/f'{name}-{arch}.deb',name,arch) for name,arch in sorted(apt.MATRIX)]

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['gpgconf','--homedir',str(cls.home),'--kill','gpg-agent'],capture_output=True)
        cls.environment.stop();cls.temp.cleanup()

    def destination(self): return Path(tempfile.mkdtemp(dir=self.root))/'apt'
    def build(self):
        path=self.destination();apt.build(path,self.packages,self.fpr,gpg=self.gpg);return path

    def test_complete_signed_four_package_repository(self):
        root=self.build();receipt=apt.verify(root,root/apt.PUBLIC_KEY,self.fpr,gpg=self.gpg)
        self.assertEqual(len(receipt['packages']),4)
        self.assertEqual({(p['Package'],p['Architecture']) for p in receipt['packages']},apt.MATRIX)
        self.assertTrue((root/'dists/stable/main/binary-arm64/Packages.xz').exists())

    def test_incomplete_duplicate_and_mixed_versions_rejected(self):
        for packages in [self.packages[:3],self.packages+[self.packages[0]],self.packages[:3]+[self.packages[0]]]:
            root=self.destination()
            with self.assertRaises(ValueError):apt.build(root,packages,self.fpr,gpg=self.gpg)
            self.assertFalse(root.exists())
        changed=fixture(self.root/'mixed.deb','locale-editor-tui','arm64','0.3.0-1')
        with self.assertRaisesRegex(ValueError,'one version'):apt.build(self.destination(),self.packages[:3]+[changed],self.fpr,gpg=self.gpg)

    def test_signed_metadata_and_payload_tampering_is_rejected(self):
        for relative in ['dists/stable/Release','dists/stable/InRelease','dists/stable/main/binary-amd64/Packages',
                         'pool/main/l/locale-editor/locale-editor-gui_0.2.0-2_arm64.deb']:
            with self.subTest(relative=relative):
                site=self.build();path=site/relative;path.write_bytes(path.read_bytes()+b'tampered')
                with self.assertRaises(ValueError):apt.verify(site,site/apt.PUBLIC_KEY,self.fpr,gpg=self.gpg)

    def test_wrong_key_missing_by_hash_and_symlink_rejected(self):
        site=self.build()
        with self.assertRaises(ValueError):apt.verify(site,site/apt.PUBLIC_KEY,'0'*40,gpg=self.gpg)
        index=site/'dists/stable/main/binary-amd64/Packages'
        by_hash=index.parent/'by-hash/SHA256'/apt.digest(index);by_hash.unlink()
        with self.assertRaisesRegex(ValueError,'missing'):apt.verify(site,site/apt.PUBLIC_KEY,self.fpr,gpg=self.gpg)
        site=self.build();(site/'external').symlink_to(self.root)
        with self.assertRaisesRegex(ValueError,'symlinks'):apt.verify(site,site/apt.PUBLIC_KEY,self.fpr,gpg=self.gpg)

    def test_previous_version_and_capacity_policy(self):
        old=[fixture(self.root/f'old-{name}-{arch}.deb',name,arch,'0.1.0-1') for name,arch in sorted(apt.MATRIX)]
        site=self.destination();receipt=apt.build(site,self.packages,self.fpr,old,self.gpg)
        self.assertEqual(len(receipt['packages']),8)
        with self.assertRaisesRegex(ValueError,'older'):apt.build(self.destination(),self.packages,self.fpr,self.packages,self.gpg)
        with patch.object(apt,'SITE_LIMIT',4096),self.assertRaisesRegex(ValueError,'budget'):
            apt.build(self.destination(),self.packages,self.fpr,gpg=self.gpg)

    def test_paths_and_debian_version_order(self):
        for path in ['../outside','/absolute','pool/../../outside','https://example.invalid/pkg.deb','pool//file','pool/./file','pool\\file']:
            with self.subTest(path=path),self.assertRaises(ValueError):apt.relative_path(path)
        for older,newer in [('0.2.0-1','0.2.0-2'),('0.9.0-1','0.10.0-1'),('1.0~rc1-1','1.0-1'),('1.0-9','1.0-10'),('1.0-1','1.0+fix-1')]:
            self.assertLess(apt.compare_versions(older,newer),0)
            self.assertGreater(apt.compare_versions(newer,older),0)
        self.assertEqual(apt.compare_versions('1.01-01','1.1-1'),0)

    @unittest.skipUnless(shutil.which('apt-get') and shutil.which('apt-cache'),'Native Linux APT verification')
    def test_real_apt_candidates_downloads_conflicts_and_rejection(self):
        site=self.build()
        for arch in apt.ARCHITECTURES:
            root=Path(tempfile.mkdtemp(dir=self.root))
            for child in ['state/lists/partial','cache/archives/partial','etc','downloads']:(root/child).mkdir(parents=True)
            (root/'state/status').touch()
            key=root/'etc/archive.gpg';apt.command([self.gpg,'--yes','--output',key,'--dearmor',site/apt.PUBLIC_KEY])
            (root/'etc/sources.list').write_text(f'deb [arch={arch} signed-by={key}] file:{site} stable main\n')
            config=root/'apt.conf'
            config.write_text(f'''Dir::State "{root}/state";
Dir::State::status "{root}/state/status";
Dir::Cache "{root}/cache";
Dir::Etc::sourcelist "{root}/etc/sources.list";
Dir::Etc::sourceparts "-";
Dir::Etc::main "-";
Dir::Etc::parts "-";
Dir::Etc::trusted "{key}";
Dir::Etc::trustedparts "-";
APT::Architecture "{arch}";
APT::Architectures {{ "{arch}"; }};
APT::Sandbox::User "{getpass.getuser()}";
Acquire::Languages "none";
''')
            env={**os.environ,'APT_CONFIG':str(config),'LC_ALL':'C'}
            apt.command(['apt-get','update','--error-on=any'],env=env)
            for package in apt.PACKAGE_NAMES:
                policy=apt.command(['apt-cache','policy',package],env=env).stdout.decode()
                self.assertIn('Candidate: 0.2.0-2',policy)
                apt.command(['apt-get','download',package],cwd=root/'downloads',env=env)
            both=subprocess.run(['apt-get','-s','install',*apt.PACKAGE_NAMES],env=env,capture_output=True)
            self.assertNotEqual(both.returncode,0)
            release=site/'dists/stable/InRelease';original=release.read_bytes()
            release.write_bytes(original.replace(b'Label: Linux Locale Editor',b'Label: Modified repository'))
            bad=subprocess.run(['apt-get','update','--error-on=any'],env=env,capture_output=True)
            self.assertNotEqual(bad.returncode,0)
            release.write_bytes(original)
            for path in (root/'downloads').glob('*.deb'):path.unlink()
            package=site/f'pool/main/l/locale-editor/locale-editor-gui_0.2.0-2_{arch}.deb'
            original=package.read_bytes();package.write_bytes(original+b'tampered')
            bad=subprocess.run(['apt-get','download','locale-editor-gui'],env=env,cwd=root/'downloads',capture_output=True)
            self.assertNotEqual(bad.returncode,0)
            package.write_bytes(original)

if __name__=='__main__':unittest.main(verbosity=2)
