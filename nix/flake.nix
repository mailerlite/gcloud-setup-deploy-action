{
  description = "Deploy packages and plugins";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      packagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          arch = if system == "x86_64-linux" then "amd64" else "arm64";
          gcloudArch = if system == "x86_64-linux" then "x86_64" else "arm";
          helm = pkgs.stdenvNoCC.mkDerivation {
            pname = "kubernetes-helm";
            version = "3.21.4";
            src = pkgs.fetchurl {
              url = "https://get.helm.sh/helm-v3.21.4-linux-${arch}.tar.gz";
              sha256 =
                {
                  amd64 = "61f88ab166748cb19604d7884cb100ae9ccb13804ddeb98e08af167eacbb6a14";
                  arm64 = "b54c04b4e0b2540bbdc08c17a121dab70e9a2ed0de5705528fec68a5fd3b85a7";
                }
                .${arch};
            };
            dontBuild = true;
            installPhase = "install -Dm755 helm $out/bin/helm";
            meta.mainProgram = "helm";
          };
          kubectl = pkgs.stdenvNoCC.mkDerivation {
            pname = "kubectl";
            version = "1.35.8";
            src = pkgs.fetchurl {
              url = "https://dl.k8s.io/release/v1.35.8/bin/linux/${arch}/kubectl";
              sha256 =
                {
                  amd64 = "874d5e72dbb819f43cff16bcd1e4f8bac5b7f2361fe1e55049b0a6c676fb0cbf";
                  arm64 = "cc749967b62f4422260bc9c0aa7a7c55f45175ae38cb8d95767b5d2b7e04c1fd";
                }
                .${arch};
            };
            dontUnpack = true;
            dontBuild = true;
            installPhase = "install -Dm755 $src $out/bin/kubectl";
          };
          # Keep SOPS on the Devbox PATH; do not hide a second version in the wrapper.
          helmSecrets = pkgs.stdenvNoCC.mkDerivation {
            pname = "helm-secrets";
            version = "4.7.7";
            src = pkgs.fetchFromGitHub {
              owner = "jkroepke";
              repo = "helm-secrets";
              rev = "v4.7.7";
              hash = "sha256-TfVKrSkr5kAwGZ6HR6m6sX3VN9LEPQYvjshYpD+R6XI=";
            };
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/helm-secrets
              cp plugin.yaml $out/helm-secrets/
              cp -r scripts $out/helm-secrets/
              wrapProgram $out/helm-secrets/scripts/run.sh --prefix PATH : ${
                pkgs.lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.findutils
                  pkgs.getopt
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.gnupg
                ]
              }
            '';
          };
          sdk = pkgs.google-cloud-sdk.overrideAttrs (old: {
            version = "575.0.1";
            src = pkgs.fetchurl {
              url = "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-575.0.1-linux-${gcloudArch}.tar.gz";
              hash =
                {
                  x86_64-linux = "sha256-OBmPp2sapkozL63KfbpF+Wxtu1zZ538XP51qZUQ+N6s=";
                  aarch64-linux = "sha256-5cOjVNTFd17M7eYmdGVH1tPcP1nbNQ9i8F28YE7sXj8=";
                }
                .${system};
            };
            installCheckPhase = builtins.replaceStrings [ old.version ] [ "575.0.1" ] old.installCheckPhase;
          });
          componentManifest = builtins.fromJSON (builtins.readFile ./gcloud-components.json);
          # The SDK wrapper already provides Python through Nix. Google adds its
          # bundled interpreter as a component dependency; exclude that duplicate
          # runtime while preserving the original, reviewed source manifest.
          withoutBundledPython =
            component:
            component
            // {
              dependencies = builtins.filter (
                name: !(pkgs.lib.hasPrefix "bundled-python" name)
              ) component.dependencies;
            };
          nixComponentManifest = componentManifest // {
            components = map withoutBundledPython componentManifest.components;
          };
          components = pkgs.callPackage "${nixpkgs}/pkgs/by-name/go/google-cloud-sdk/components.nix" {
            snapshotPath = pkgs.writeText "gcloud-components-nix.json" (builtins.toJSON nixComponentManifest);
          };
          withExtraComponents =
            pkgs.callPackage "${nixpkgs}/pkgs/by-name/go/google-cloud-sdk/withExtraComponents.nix"
              {
                google-cloud-sdk = sdk;
                inherit components;
              };
        in
        {
          inherit kubectl;
          gcloud = withExtraComponents [ components.gke-gcloud-auth-plugin ];
          helm = pkgs.wrapHelm helm { plugins = [ helmSecrets ]; };
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
                helm version --short | grep -F 'v3.21.4'
                helm plugin list | grep -E 'secrets[[:space:]]+4.7.7'
                kubectl version --client -o json | grep -F 'v1.35.8'
                gcloud --version | grep -F 'Google Cloud SDK 575.0.1'
                gke-gcloud-auth-plugin --version
                touch "$out"
              '';
        }
      );
    };
}
