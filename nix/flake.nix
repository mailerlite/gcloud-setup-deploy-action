{
  description = "Pinned deploy packages and plugins for the MailerLite toolchain";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      versions = {
        helm = "3.21.4";
        helmSecrets = "4.7.6";
        kubectl = "1.35.8";
        skaffold = "2.24.0";
        cue = "0.17.1";
        gh = "2.97.0";
        sops = "3.13.3";
        jq = "1.7.1";
      };
      packagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          arch = if system == "x86_64-linux" then "amd64" else "arm64";
          # Official static Linux release artifacts, checked against upstream SHA256s.
          # `bin` is the executable's path inside a tarball; plain binaries omit it.
          release =
            {
              pname,
              version,
              url,
              sha256,
              bin ? null,
            }:
            pkgs.stdenvNoCC.mkDerivation {
              inherit pname version;
              src = pkgs.fetchurl {
                inherit url;
                sha256 = sha256.${arch};
              };
              sourceRoot = ".";
              dontUnpack = bin == null;
              dontBuild = true;
              installPhase = "install -Dm755 ${if bin == null then "$src" else bin} $out/bin/${pname}";
              meta.mainProgram = pname;
            };
          helm = release {
            pname = "helm";
            version = versions.helm;
            url = "https://get.helm.sh/helm-v${versions.helm}-linux-${arch}.tar.gz";
            bin = "linux-${arch}/helm";
            sha256 = {
              amd64 = "61f88ab166748cb19604d7884cb100ae9ccb13804ddeb98e08af167eacbb6a14";
              arm64 = "b54c04b4e0b2540bbdc08c17a121dab70e9a2ed0de5705528fec68a5fd3b85a7";
            };
          };
          helmSecrets = pkgs.kubernetes-helmPlugins.helm-secrets.overrideAttrs (_: {
            version = versions.helmSecrets;
            src = pkgs.fetchFromGitHub {
              owner = "jkroepke";
              repo = "helm-secrets";
              rev = "v${versions.helmSecrets}";
              hash = "sha256-gCsXnZCvQqc5PIQGheOdzZ1YSUNDhbMvJIROMGA65Jg=";
            };
            postPatch = ''
              sed -i 's/^version:.*/version: "${versions.helmSecrets}"/' plugin.yaml
            '';
          });
          # gcloud and its GKE auth plugin follow the nixpkgs release pinned in
          # flake.lock; bump them by updating the lock.
          sdk = pkgs.google-cloud-sdk;
        in
        {
          gcloud = sdk.withExtraComponents [ sdk.components.gke-gcloud-auth-plugin ];
          helm = pkgs.wrapHelm helm { plugins = [ helmSecrets ]; };
          # The nixpkgs sops is also the one the helm-secrets wrapper uses; the
          # version check fails if a lock bump moves it off the pin.
          inherit (pkgs) sops;
          kubectl = release {
            pname = "kubectl";
            version = versions.kubectl;
            url = "https://dl.k8s.io/release/v${versions.kubectl}/bin/linux/${arch}/kubectl";
            sha256 = {
              amd64 = "874d5e72dbb819f43cff16bcd1e4f8bac5b7f2361fe1e55049b0a6c676fb0cbf";
              arm64 = "cc749967b62f4422260bc9c0aa7a7c55f45175ae38cb8d95767b5d2b7e04c1fd";
            };
          };
          skaffold = release {
            pname = "skaffold";
            version = versions.skaffold;
            url = "https://github.com/GoogleContainerTools/skaffold/releases/download/v${versions.skaffold}/skaffold-linux-${arch}";
            sha256 = {
              amd64 = "702344081860a587c57937cd55dfa2e70f124c05d6fb845319832ee23fd144a8";
              arm64 = "a8331e599223ad9df489b4d956704505b888c24b0d89abf26a0fe61c58d10fc5";
            };
          };
          # cue publishes no checksum file; these are GitHub's recorded asset digests.
          cue = release {
            pname = "cue";
            version = versions.cue;
            url = "https://github.com/cue-lang/cue/releases/download/v${versions.cue}/cue_v${versions.cue}_linux_${arch}.tar.gz";
            bin = "cue";
            sha256 = {
              amd64 = "a39b0c97695069d95d276d99be0f5dbabb081d801bfdc9ba49b76efaf94e2369";
              arm64 = "0d729be30d52c952ca38fc9dcb692caa09d8463fa0b64df5781312779183fbcd";
            };
          };
          gh = release {
            pname = "gh";
            version = versions.gh;
            url = "https://github.com/cli/cli/releases/download/v${versions.gh}/gh_${versions.gh}_linux_${arch}.tar.gz";
            bin = "gh_${versions.gh}_linux_${arch}/bin/gh";
            sha256 = {
              amd64 = "a2c9b8497e1f85b1ad0dfcb78b5a622e098801b8e461e459e88e1ee12f018112";
              arm64 = "73ea440ecad9c9e284429997ee6f93577bc6f7bc6fba357ef62c53ad8fb641a5";
            };
          };
          jq = release {
            pname = "jq";
            version = versions.jq;
            url = "https://github.com/jqlang/jq/releases/download/jq-${versions.jq}/jq-linux-${arch}";
            sha256 = {
              amd64 = "5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5";
              arm64 = "4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5";
            };
          };
        };
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          tools = packagesFor system;
        in
        tools
        // {
          default = pkgs.buildEnv {
            name = "mlr-deploy-tools";
            paths = builtins.attrValues tools;
          };
        }
      );
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.age
              pkgs.shellcheck
              pkgs.actionlint
              pkgs.nixfmt
              pkgs.python3
            ];
          };
        }
      );
      # Setup builds this check too, so every provisioned toolchain is version-verified.
      checks = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          tools = packagesFor system;
        in
        {
          versions =
            pkgs.runCommand "deploy-toolchain-checks"
              {
                nativeBuildInputs = builtins.attrValues tools;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                helm version --short | grep -F 'v${versions.helm}'
                helm plugin list | grep -E 'secrets[[:space:]]+${versions.helmSecrets}'
                kubectl version --client -o json | grep -F 'v${versions.kubectl}'
                skaffold version | grep -Fx 'v${versions.skaffold}'
                cue version | grep -Fx 'cue version v${versions.cue}'
                gh --version | grep -F 'gh version ${versions.gh} '
                sops --disable-version-check --version | grep -Fx 'sops ${versions.sops}'
                jq --version | grep -Fx 'jq-${versions.jq}'
                gcloud --version | grep -F 'Google Cloud SDK ${pkgs.google-cloud-sdk.version}'
                gke-gcloud-auth-plugin --version
                touch "$out"
              '';
        }
      );
    };
}
