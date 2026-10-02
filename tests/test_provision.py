"""Configuration failures must happen before installing or exporting tools."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProvisionTests(unittest.TestCase):
    def run_setup(self, missing=None, corrupt=None, paths=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            (source / 'nix').mkdir(parents=True)
            if missing != 'nix/flake.lock':
                (source / 'nix/flake.lock').write_text('not json' if corrupt else '{}')
            if missing != 'nix/flake.nix':
                (source / 'nix/flake.nix').write_text('{}')
            if missing != 'nix/store-paths.json':
                (source / 'nix/store-paths.json').write_text(paths or json.dumps(
                    {'x86_64-linux': {'tools': '/nix/store/a-tools', 'check': '/nix/store/b-check'}}))
            env = os.environ | {
                'RUNNER_TEMP': str(root), 'RUNNER_OS': 'Linux', 'RUNNER_ARCH': 'X64',
                'GITHUB_PATH': str(root / 'path'), 'GITHUB_ENV': str(root / 'env'),
                'GITHUB_STEP_SUMMARY': str(root / 'summary'),
            }
            result = subprocess.run(
                ['bash', str(ROOT / 'setup/provision.sh'), str(source)],
                env=env, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'path').exists(), 'failure exported PATH')
            self.assertFalse((root / 'env').exists(), 'failure exported environment')
            return result.stderr

    def test_missing_required_files(self):
        for name in ('nix/flake.nix', 'nix/flake.lock', 'nix/store-paths.json'):
            with self.subTest(name=name):
                self.assertIn('Missing required file: ' + name, self.run_setup(missing=name))

    def test_corrupt_lock(self):
        self.assertIn('Invalid JSON: nix/flake.lock', self.run_setup(corrupt=True))

    def test_invalid_store_paths(self):
        for paths in ('not json', '{}', json.dumps({'x86_64-linux': {'tools': 'x', 'check': 'y'}})):
            with self.subTest(paths=paths):
                self.assertIn('Invalid nix/store-paths.json', self.run_setup(paths=paths))


if __name__ == '__main__':
    unittest.main()
