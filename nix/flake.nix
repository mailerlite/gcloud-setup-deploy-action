{
  # The two tools devbox's flat pkg@version list can't express:
  #  - gcloud WITH gke-gcloud-auth-plugin (withExtraComponents)
  #  - helm WITH helm-secrets (wrapHelm), pinned to helm 3 via stable
  # Everything else is version-pinned in ../devbox.json.
  description = "gcloud(+gke-gcloud-auth-plugin) and helm(+helm-secrets) for the deploy toolchain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # helm pinned to stable: the shared action.yaml runs
    # `helm registry login https://…`, which helm 4 (unstable) rejects.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, nixpkgs-stable }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s:
        f nixpkgs.legacyPackages.${s} nixpkgs-stable.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs: stable: {
        default = pkgs.buildEnv {
          name = "mlr-deploy-nix-tools";
          paths = [
            (pkgs.google-cloud-sdk.withExtraComponents [
              pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
            ])
            (stable.wrapHelm stable.kubernetes-helm {
              plugins = [ stable.kubernetes-helmPlugins.helm-secrets ];
            })
          ];
        };
      });
    };
}
