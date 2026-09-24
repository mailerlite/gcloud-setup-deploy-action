"""Configuration failures must happen before installing or exporting tools."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProvisionTests(unittest.TestCase):
    def run_setup(self, missing=None, corrupt=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            (source / 'nix').mkdir(parents=True)
            for name in ('devbox.json', 'devbox.lock', 'nix/flake.lock', 'nix/gcloud-components.json'):
                if name != missing:
                    (source / name).write_text('not json' if name == corrupt else '{}')
            if missing != 'nix/flake.nix':
                (source / 'nix/flake.nix').write_text('{}')
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
        for name in ('devbox.json', 'devbox.lock', 'nix/flake.nix', 'nix/flake.lock', 'nix/gcloud-components.json'):
            with self.subTest(name=name):
                self.assertIn('Missing required file: ' + name, self.run_setup(missing=name))

    def test_corrupt_json(self):
        for name in ('devbox.json', 'devbox.lock', 'nix/flake.lock', 'nix/gcloud-components.json'):
            with self.subTest(name=name):
                self.assertIn('Invalid JSON: ' + name, self.run_setup(corrupt=name))


if __name__ == '__main__':
    unittest.main()
