import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CleanupTests(unittest.TestCase):
    def test_missing_setup_is_a_noop(self):
        env = dict(os.environ)
        env.pop('MLR_TOOLCHAIN_AUTH_DIR', None)
        result = subprocess.run(['bash', str(ROOT / 'cleanup/cleanup.sh')], env=env)
        self.assertEqual(result.returncode, 0)

    def test_unowned_directory_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            keep = root / 'unrelated'
            keep.mkdir()
            (keep / 'important').write_text('keep me')
            result = subprocess.run(
                ['bash', str(ROOT / 'cleanup/cleanup.sh')],
                env=os.environ | {'RUNNER_TEMP': str(root), 'MLR_TOOLCHAIN_AUTH_DIR': str(keep)},
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((keep / 'important').read_text(), 'keep me')


if __name__ == '__main__':
    unittest.main()
