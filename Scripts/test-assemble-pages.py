#!/usr/bin/env python3
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('pages',Path(__file__).with_name('assemble-pages.py'))
pages=importlib.util.module_from_spec(spec);spec.loader.exec_module(pages)

class SnapshotTests(unittest.TestCase):
    def test_safe_snapshot_and_reject_traversal_links_and_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for index,mode in enumerate(('safe','traversal','symlink','hardlink','duplicate')):
                archive=root/f'{mode}.tar.gz';output=root/f'out-{index}';output.mkdir()
                with tarfile.open(archive,'w:gz') as tar:
                    info=tarfile.TarInfo('../escape' if mode=='traversal' else 'apt/marker')
                    if mode in ('symlink','hardlink'):
                        info.type=tarfile.SYMTYPE if mode=='symlink' else tarfile.LNKTYPE;info.linkname='/etc/passwd';tar.addfile(info)
                    else:
                        info.size=2;tar.addfile(info,io.BytesIO(b'ok'))
                        if mode=='duplicate':tar.addfile(info,io.BytesIO(b'ok'))
                if mode=='safe':
                    pages.unpack(archive,output);self.assertEqual((output/'apt/marker').read_bytes(),b'ok')
                else:
                    with self.assertRaises((ValueError,FileExistsError)):pages.unpack(archive,output)
if __name__=='__main__':unittest.main(verbosity=2)
