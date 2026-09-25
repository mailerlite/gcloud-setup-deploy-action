import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RegistryTests(unittest.TestCase):
    def test_invalid_registry_is_rejected_before_authentication(self):
        for host in ('https://registry.example', 'registry.example/path', 'x;echo bad'):
            with self.subTest(host=host):
                result = subprocess.run(
                    ['bash', str(ROOT / 'scripts/registry-login.sh')],
                    env=os.environ | {'ARTIFACT_REGISTRY': host},
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('must be a hostname', result.stderr)

    def test_selected_registry_receives_token_on_stdin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gcloud = root / 'gcloud'
            gcloud.write_text('#!/bin/sh\ncase "$*" in\n*print-access-token) printf fixture-token;;\nesac\n')
            helm = root / 'helm'
            helm.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARGS_FILE"\ncat > "$TOKEN_FILE"\n')
            for executable in (gcloud, helm):
                executable.chmod(0o755)
            env = os.environ | {
                'PATH': f'{root}:{os.environ["PATH"]}',
                'ARTIFACT_REGISTRY': 'us-east1-docker.pkg.dev',
                'ARGS_FILE': str(root / 'args'), 'TOKEN_FILE': str(root / 'token'),
            }
            result = subprocess.run(['bash', str(ROOT / 'scripts/registry-login.sh')],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / 'args').read_text().splitlines(), [
                'registry', 'login', '--username', 'oauth2accesstoken',
                '--password-stdin', 'us-east1-docker.pkg.dev',
            ])
            self.assertEqual((root / 'token').read_text(), 'fixture-token')
            self.assertNotIn('fixture-token', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
