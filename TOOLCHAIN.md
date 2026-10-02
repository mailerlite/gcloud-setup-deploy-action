# Deploy toolchain

This candidate pins the Docker baseline's Helm 3.21.4, kubectl 1.35.8,
skaffold 2.24.0, cue 0.17.1, gh 2.97.0, sops 3.13.3 and jq 1.7.1 exactly, and
helm-secrets at 4.7.6. All of them are defined in a single Nix flake. gcloud and its GKE auth plugin follow the nixpkgs release
pinned in `nix/flake.lock` (565.0.0 today) rather than the Docker image's 575.0.1.
Docker CLI/buildx/daemon, Python 3, Bash and GNU coreutils are runner prerequisites.
The gcloud wrapper supplies its own Python through Nix.

The target runners are Ubuntu 24.04 x64 and arm64, including the existing Warp
runners. Linux CI and authenticated pilot validation must pass before these targets
are declared supported in a release. macOS and persistent self-hosted runners are
not supported by setup.

## How the pieces fit

- `nix/flake.nix` defines every tool and its version in one `versions` set, and a
  `checks.<system>.versions` derivation that asserts them. `nix/flake.lock` pins
  the maintained nixpkgs collection used for gcloud, sops and the Helm plugin.
- `setup/action.yaml` pins the installer and upstream Nix 2.35.2.
  `setup/provision.sh` builds the flake's default package and version check from
  the action's `nix/` directory without updating its lock, then exports the single
  tool directory and runtime environment for later steps.
- `cleanup/` removes the separate runtime authentication directory and `/tmp/key.json`.
  Use it after the job's final tool operation with `if: always()`.

Setup uses public package sources, cache.nixos.org and the SRE-run Attic cache
described under [Binary cache](#binary-cache). It needs one secret, the Attic pull
token, passed as the `attic-token` input. GitHub downloads authenticate with the
short-lived `${{ github.token }}` configured by the Nix installer; no PAT is
required. The installer-managed Nix configuration contains runtime
authentication state and must not be included in future snapshots. Setup does not
save snapshots. Provisioning
has a five-minute timeout after the Nix installer; the calling job must also have a
finite timeout to bound installer failures. Failed setup stops the job before auth.
The job summary shows executable paths, versions and configuration hashes.

## Usage

Pin setup, deploy and cleanup to the same full SHA of a tested action release.
The snippets below describe the step order; substitute the actual released SHA.

```yaml
- uses: mailerlite/gcloud-setup-deploy-action/setup@RELEASE_SHA
  with:
    attic-token: ${{ secrets.ATTIC_PULL_TOKEN }}
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

## Binary cache

Setup pulls from the private Attic cache `deploy-toolchain` at
`https://attic.litehub.io` (GKE europe-west4, objects in GCS). `setup/action.yaml`
pins its URL and public key `deploy-toolchain:9p4kYIdED5ifmOnE591RNJQde3ELXQjb0HRSbHJo5UM=`;
Nix only accepts paths signed by that key or cache.nixos.org's. The token
controls who can download, the key controls what runners trust.

The cache holds only paths cache.nixos.org does not serve: the release binaries,
the Helm wrapper and plugin, the GKE auth plugin, gcloud's component join, the tool
environment and its version check. Attic skips paths signed by `cache.nixos.org-1`
on push, and its priority 41 ranks after cache.nixos.org's 40, so shared paths such
as the gcloud SDK keep coming from that CDN. One cache serves every branch and
environment: store paths are derived from `nix/flake.nix` and `nix/flake.lock`, so
callers pinning the same action SHA share one toolchain.

Two tokens, both kept in 1Password and synced to GitHub:

- `ATTIC_PULL_TOKEN` (pull `deploy-toolchain`): organization secret for repositories
  that deploy and for this repository's CI. Any job running caller code can read
  it, so it must never carry push scope.
- `ATTIC_PUSH_TOKEN` (pull and push `deploy-toolchain`): secret of this repository
  only. Write access here is limited to SRE; anyone who can push could otherwise
  replace the binaries that receive deployment credentials.

`toolchain.yml` pushes the tool environment and version check on both architectures
after every check has passed, so a commit's toolchain is cached once its CI is green.
Pin callers only to such commits; an uncached toolchain still installs, but builds
from upstream sources.

`setup/cache-auth.sh` writes the token to a netrc in `RUNNER_TEMP` before Nix is
installed and checks it against the cache. A rejected token (HTTP 401/403/404) fails
setup; an unreachable cache only warns, and Nix fetches and builds the missing paths
itself. Cleanup removes the netrc.

Operations, run by SRE with an admin token on the Attic server:

- Mint tokens with `atticadm make-token --sub <name> --validity '90 days' --pull deploy-toolchain`
  (add `--push deploy-toolchain` for the CI token) and rotate them before expiry.
  Attic tokens cannot be revoked one by one; rotating the server's token secret
  invalidates all of them.
- Retention (`attic cache configure litehub:deploy-toolchain --retention-period ...`)
  must outlast every pinned and rollback action SHA.
- Regenerating the keypair (`--regenerate-keypair`) requires the new public key in
  `setup/action.yaml` and a new action release; old releases stop trusting the cache.

## Update and extend

SRE owns the manifests, custom definitions, security findings and releases. Review
updates and upstream support status regularly and urgently for security fixes.

Every version lives in the `versions` set at the top of `nix/flake.nix`. The
custom definitions exist because the exact Docker versions are not all available
in the maintained package collection:

- Helm, kubectl, skaffold, cue, gh and jq use the `release` helper: official static
  Linux release artifacts with SHA256s for both architectures. Update the version
  and both checksums together, taken from the upstream checksum file (cue publishes
  none; use the release asset digests from
  `gh api repos/cue-lang/cue/releases/tags/vX.Y.Z`). Tarballs also name the
  executable's path inside the archive.
- helm-secrets reuses the nixpkgs recipe and wrapper, overriding only the source
  tag. Update the version and the `nix store prefetch-file --json --unpack URL`
  hash together.
- sops, gcloud and the GKE auth plugin are the stock nixpkgs packages; the Helm
  wrapper uses the same sops. Bump them with `nix flake update --flake ./nix`.
  The version check fails if the bump moves sops off its pin; either update the
  pin or package sops like the release tools. Review the gcloud version change in
  the summary and release notes, and run package checks.

Keep the custom definitions only while the exact versions require them. Prefer
maintained nixpkgs recipes when matching packages become available. `nix/flake.nix`
tracks the `nixos-26.05` stable branch on purpose: lock bumps bring backported
fixes rather than major version jumps.

## Validation and release

`toolchain.yml` runs on PRs, feature branch pushes and manual dispatches, with
read-only repository permissions and no deployment credentials; it only receives
the Attic tokens. It covers both
Linux architectures, actual toolchain installation, Nix package checks, static checks,
missing/corrupt configuration, repeated setup, version checks, Docker availability
and Helm secret decryption using a local age fixture.

Run local script tests with `python3 -m unittest discover -s tests -p 'test_*.py'`.
On a supported Linux runner after setup, use `nix develop ./nix --command bash
tests/check.sh` and `nix flake check ./nix --no-update-lock-file`.

Before publishing, retain passing run links for both architectures, review the
code and complete a manual dev deployment. Verify
cluster version skew before contacting the pilot cluster. Review complete-toolchain
vulnerability/SBOM coverage and record findings; missing coverage requires a named
owner, rationale and review date. This candidate does not yet replace Docker's
Trivy/Dependency-Track coverage and must not be released on lint results alone.

Publish an immutable action version with package versions, supported runners,
validation links, known limits and rollback notes. Verify installation from that
published SHA. Pilot workflows stay on their dedicated branch, pinned by commit;
no workflow release or merge into `workflows/main` is required.

## Troubleshooting and rollback

Failures name the setup phase. Check the first failing
command, network availability and package versions. Never regenerate the lock during
a deployment, bypass the version/path checks, or install missing tools from the host.
If a fresh install exceeds five minutes, investigate its downloads/builds before
changing the budget. Do not introduce snapshots until credential exclusion is tested.

Restore the recorded Docker workflow commit and image digest to roll back. Restore
caller references too: changing a reusable workflow does not move SHA-pinned callers.
Alternatively restore a previous tested action SHA for setup, deploy and cleanup.
Keep all rollback references and artifacts available throughout the evaluation.
