{
  # Deploy toolchain that replaces the swiss-army-knife CI container.
  # `nix profile install .#ci` puts the whole toolchain on PATH; the
  # setup/ composite action calls it before gcloud/skaffold/etc run.
  description = "MailerLite deploy toolchain (replaces swiss-army-knife)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # helm is pinned to stable on purpose: the shared action.yaml runs
    # `helm registry login https://…`, which helm 4 (current unstable)
    # rejects ("invalid registry"). swiss-army-knife shipped helm 3.x, so
    # match that until the action is updated for helm 4.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, nixpkgs-stable }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s:
        f nixpkgs.legacyPackages.${s} nixpkgs-stable.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs: stable:
        let
          # gcloud + the GKE auth plugin as a first-class component — the exact
          # thing the Dockerfile does imperatively and mise-oci cannot do at all.
          gcloud = pkgs.google-cloud-sdk.withExtraComponents [
            pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
          ];

          # helm 3 (from stable) with the helm-secrets plugin bound in.
          helm = stable.wrapHelm stable.kubernetes-helm {
            plugins = [ stable.kubernetes-helmPlugins.helm-secrets ];
          };
        in
        rec {
          ci = pkgs.buildEnv {
            name = "mlr-deploy-toolchain";
            paths = [
              gcloud
              helm
              pkgs.skaffold
              pkgs.kubectl
              pkgs.cue
              pkgs.gh
              pkgs.sops
              pkgs.jq
            ];
          };
          default = ci;
        });
    };
}
