"""Execute the production C type comparator on this host, not a Python model."""
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProductionTypeEncoding(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='stheno-type-test-', dir=os.environ.get('TMPDIR'))
        clang = shutil.which('clang')
        if not clang:
            raise unittest.SkipTest('clang not available')
        source = ROOT / 'Sources/Support/SthenoTypeEncoding.c'
        if not source.is_file():
            raise AssertionError('native admission has no production type comparator')
        library = Path(cls.tmp.name) / ('encoding.dylib' if os.uname().sysname == 'Darwin' else 'encoding.so')
        command = [clang, '-std=c11', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC', str(source), '-o', str(library)]
        subprocess.run(command, check=True, capture_output=True, text=True)
        cls.library = ctypes.CDLL(str(library))
        cls.compare = cls.library.SthenoTypesAreABICompatible
        cls.compare.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_bool]
        cls.compare.restype = ctypes.c_bool

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_rejects_the_shipped_object_void_and_scalar_confusions(self):
        for original, replacement in [(b'v', b'@'), (b'@', b'v'), (b'Q', b'@'),
                                      (b'@', b'q'), (b'^v', b'@'),
                                      (b'{CGRect={CGPoint=dd}{CGSize=dd}}', b'@')]:
            with self.subTest(original=original, replacement=replacement):
                self.assertFalse(self.compare(original, replacement, False))

    def test_blocks_are_distinct_except_one_way_explicit_opaque_forwarding(self):
        self.assertFalse(self.compare(b'@?', b'@', False))
        self.assertFalse(self.compare(b'@', b'@?', True))
        self.assertTrue(self.compare(b'@?', b'@', True))
        self.assertTrue(self.compare(b'@?', b'@?', False))
        self.assertFalse(self.compare(b'^v', b'@', True))

    def test_retains_exact_aggregate_pointer_and_integer_abi(self):
        for encoding in [b'v', b'B', b'q', b'Q', b'i', b'^v', b':',
                         b'{CGRect={CGPoint=dd}{CGSize=dd}}']:
            self.assertTrue(self.compare(encoding, encoding, False), encoding)
        self.assertFalse(self.compare(b'B', b'c', False))
        self.assertFalse(self.compare(b'q', b'i', False))
        self.assertFalse(self.compare(b'^i', b'^v', False))

    def test_qualifiers_and_typed_objects_do_not_change_outer_abi(self):
        self.assertTrue(self.compare(b'r@"NSString"', b'@', False))
        self.assertTrue(self.compare(b'@', b'@"NSObject"', False))
        self.assertTrue(self.compare(b'r^v', b'^v', False))
        self.assertFalse(self.compare(None, b'@', False))
        self.assertFalse(self.compare(b'', b'', False))
        self.assertFalse(self.compare(b'?', b'?', False))


if __name__ == '__main__':
    unittest.main()
