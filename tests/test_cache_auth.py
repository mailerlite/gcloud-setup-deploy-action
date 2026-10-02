"""Bad Attic tokens must fail before any netrc is written or the network is used."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CacheAuthTests(unittest.TestCase):
    def run_auth(self, token):
        with tempfile.TemporaryDirectory() as directory:
            env = os.environ | {'RUNNER_TEMP': directory, 'ATTIC_TOKEN': token}
            result = subprocess.run(
                ['bash', str(ROOT / 'setup/cache-auth.sh')],
                env=env, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(directory) / 'mlr-nix-netrc').exists(), 'failure wrote netrc')
            return result.stderr

    def test_empty_token(self):
        self.assertIn('attic-token is empty', self.run_auth(''))

    def test_token_cannot_inject_netrc_entries(self):
        for token in ('abc\nmachine evil.example', 'abc def'):
            with self.subTest(token=token):
                self.assertIn('unexpected characters', self.run_auth(token))


if __name__ == '__main__':
    unittest.main()
