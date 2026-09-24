# Deploy toolchain

This candidate preserves the Docker baseline's explicitly versioned CLIs:
gcloud 575.0.1, Helm 3.21.4, helm-secrets 4.7.7, kubectl 1.35.8,
skaffold 2.24.0, cue 0.17.1, gh 2.97.0 and sops 3.13.3. jq remains pinned
at 1.7.1. Docker CLI/buildx/daemon, Python 3, Bash and GNU coreutils are runner
prerequisites. The gcloud wrapper supplies its own Python and helm-secrets supplies
GnuPG and shell utilities through Nix.

The target runners are Ubuntu 24.04 x64 and arm64, including the existing Warp
runners. Linux CI and authenticated pilot validation must pass before these targets
are declared supported in a release. macOS and persistent self-hosted runners are
not supported by setup.

## How the pieces fit

- `devbox.json` selects ordinary CLI versions; `devbox.lock` records their exact
  package revisions and store outputs.
- `nix/flake.nix` composes gcloud/GKE and Helm/helm-secrets and supplies kubectl.
  `nix/flake.lock` pins the maintained nixpkgs collection used by these recipes.
- `setup/action.yaml` pins the installer, upstream Nix 2.35.2 and Devbox 0.17.5.
  `setup/provision.sh` copies only package configuration into a unique temporary
  directory, installs it, checks locks and paths, and exports tools for later steps.
- `cleanup/` removes the separate runtime authentication directory and `/tmp/key.json`.
  Use it after the job's final tool operation with `if: always()`.

Setup uses public package sources/caches. It does not save snapshots. Provisioning
has a five-minute timeout after the Nix installer; the calling job must also have a
finite timeout to bound installer failures. Failed setup stops the job before auth.
The job summary shows executable paths, versions and configuration hashes.

## Usage

Pin setup, deploy and cleanup to the same full SHA of a tested action release.
The snippets below describe the step order; substitute the actual released SHA.

```yaml
- uses: mailerlite/gcloud-setup-deploy-action/setup@RELEASE_SHA
- uses: mailerlite/gcloud-setup-deploy-action@RELEASE_SHA
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: your-dev-project
    zone: your-dev-zone
    cluster: your-dev-cluster
    skaffold_profile: branch
# Any further Helm/kubectl operations go before cleanup.
- uses: mailerlite/gcloud-setup-deploy-action/cleanup@RELEASE_SHA
  if: always()
```

Setup provides an isolated gcloud configuration, Docker configuration, kubeconfig
and Helm registry file. It preserves `GOOGLE_APPLICATION_CREDENTIALS=/tmp/key.json`
and `USE_GKE_GCLOUD_AUTH_PLUGIN=True`. Do not cache the auth directory or run two
credentialed deployments concurrently inside one job. Repeat setup only before
authentication or after cleanup; it deliberately provisions again rather than
trusting an existing PATH.

## Update and extend

SRE owns the manifests, custom definitions, security findings and releases. Review
updates and upstream support status regularly and urgently for security fixes.

For an ordinary CLI update or addition, change its exact version in `devbox.json`
and run Devbox 0.17.5 `devbox update --no-install` from the repository root.
Review the changed versions and both locks. This version's update command may add
an absolute local `path:./nix` entry to `devbox.lock`; remove that entry before
committing. Local flakes are resolved from `devbox.json`, not that entry, as shown
in the [pinned Devbox implementation](https://github.com/jetify-com/devbox/blob/0.17.5/internal/devpkg/package.go).
CI verifies relocation and unchanged locks during actual installation.

The custom Nix packages exist because the exact Docker versions are not all
available through Devbox or the maintained package collection:

- Helm and kubectl use official Linux release artifacts with upstream SHA256s for
  both architectures. Update the version, URLs and both checksums together.
- gcloud reuses nixpkgs' packaging with the exact SDK archives. Recompute both
  archive hashes with `nix store prefetch-file --json URL`. Fetch the matching
  `https://dl.google.com/dl/cloudsdk/channels/rapid/components-vVERSION.json` into
  `nix/gcloud-components.json`; it includes component source hashes. Never use the
  moving `components-2.json` manifest. Review the changes and run package checks.
- helm-secrets uses its exact tagged source and `nix store prefetch-file --json
  --unpack URL` hash. Its wrapper supplies shell dependencies, while SOPS is selected
  through Devbox so a second SOPS version cannot silently take precedence.

Keep the custom definitions only while the exact versions require them. Prefer
maintained nixpkgs recipes when matching packages become available. gcloud's
component composition uses files inside the pinned nixpkgs tree: recheck those
interfaces when updating `nix/flake.lock`. This extra maintenance is an explicit cost
of matching Docker exactly.

## Validation and release

`toolchain.yml` runs on PRs, feature branch pushes and manual dispatches, with
read-only repository permissions and no deployment credentials. It covers both
Linux architectures, actual Devbox installation, Nix package checks, static checks,
missing/corrupt configuration, repeated setup, version checks, Docker availability
and Helm secret decryption using a local age fixture.

Run local script tests with `python3 -m unittest discover -s tests -p 'test_*.py'`.
On a supported Linux runner after setup, use `nix develop ./nix --command bash
tests/check.sh` and `nix flake check ./nix --no-update-lock-file`.

Before publishing, retain passing run links for both architectures, review the
code and complete the manual dev operations in `evaluation/README.md`. Verify
cluster version skew before contacting the pilot cluster. Review complete-toolchain
vulnerability/SBOM coverage and record findings; missing coverage requires a named
owner, rationale and review date. This candidate does not yet replace Docker's
Trivy/Dependency-Track coverage and must not be released on lint results alone.

Publish an immutable action version with package versions, supported runners,
validation links, known limits and rollback notes. Verify installation from that
published SHA. Pilot workflows stay on their dedicated branch, pinned by commit;
no workflow release or merge into `workflows/main` is required.

## Troubleshooting and rollback

Failures name the setup phase and temporary work directory. Check the first failing
command, network availability and package versions. Never regenerate locks during
a deployment, bypass the version/path checks, or install missing tools from the host.
If a fresh install exceeds five minutes, investigate its downloads/builds before
changing the budget. Do not introduce snapshots until credential exclusion is tested.

Restore the recorded Docker workflow commit and image digest to roll back. Restore
caller references too: changing a reusable workflow does not move SHA-pinned callers.
Alternatively restore a previous tested action SHA for setup, deploy and cleanup.
Keep all rollback references and artifacts available throughout the evaluation.
