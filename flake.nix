{
  # Deploy toolchain that replaces the swiss-army-knife CI container.
  # `nix profile install .#ci` puts the whole toolchain on PATH; the
  # composite action(s) in this repo call it before running gcloud/skaffold/etc.
  description = "MailerLite deploy toolchain (replaces swiss-army-knife)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs:
        let
          # gcloud + the GKE auth plugin as a first-class component — the exact
          # thing the Dockerfile does imperatively and mise-oci cannot do at all.
          gcloud = pkgs.google-cloud-sdk.withExtraComponents [
            pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
          ];

          # helm with the helm-secrets plugin bound in (skaffold's helm deployer
          # + the current image both expect it available).
          helm = pkgs.wrapHelm pkgs.kubernetes-helm {
            plugins = [ pkgs.kubernetes-helmPlugins.helm-secrets ];
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
