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
      helmSecretsVersion = "4.7.6";
      packagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          arch = if system == "x86_64-linux" then "amd64" else "arm64";
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

          helmSecrets = pkgs.kubernetes-helmPlugins.helm-secrets.overrideAttrs (_: {
            version = helmSecretsVersion;
            src = pkgs.fetchFromGitHub {
              owner = "jkroepke";
              repo = "helm-secrets";
              rev = "v${helmSecretsVersion}";
              hash = "sha256-gCsXnZCvQqc5PIQGheOdzZ1YSUNDhbMvJIROMGA65Jg=";
            };
            postPatch = ''
              sed -i 's/^version:.*/version: "${helmSecretsVersion}"/' plugin.yaml
            '';
          });
          # gcloud and its GKE auth plugin follow the nixpkgs release pinned in
          # flake.lock; bump them by updating the lock.
          sdk = pkgs.google-cloud-sdk;
        in
        {
          inherit kubectl;
          gcloud = sdk.withExtraComponents [ sdk.components.gke-gcloud-auth-plugin ];
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
                helm plugin list | grep -E 'secrets[[:space:]]+${helmSecretsVersion}'
                kubectl version --client -o json | grep -F 'v1.35.8'
                gcloud --version | grep -F 'Google Cloud SDK ${pkgs.google-cloud-sdk.version}'
                gke-gcloud-auth-plugin --version
                touch "$out"
              '';
        }
      );
    };
}
