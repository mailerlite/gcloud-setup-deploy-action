#!/usr/bin/env bash
set -euo pipefail
python3 -m unittest discover -s tests -p 'test_*.py'
shellcheck setup/*.sh cleanup/*.sh scripts/*.sh tests/*.sh
actionlint .github/workflows/toolchain.yml
nixfmt --check nix/flake.nix
