# Breaking Changes

Please be aware that we introduced a breaking change here in that you must use https://cloud.google.com/sdk/docs/release-notes

Gcloud SDK version 319 and above to allow container commands to be run as not part of the beta group.

# Required Inputs: *

**service_account_key** - A **base64-encoded** Google service account key that has access to an artifact registry in the configured project.

**project** - The Google account project

**zone** - The Zone that is required

# Optional Inputs:

Based on what you wish to do in this action.

**cluster** - The k8s cluster name that gcloud auth and skaffold will use, this input is used to toggle the skaffold deployment, without it cluster auth will not be run.

**skaffold_profile** - The skaffold Profile that is run, when the above is in use, is required when above is on.

**docker_slug** - Only required when building a docker image e.g: europe-docker.pkg.dev/mailergroup/autossl-caddy/autossl-caddy

**docker_file** - Only required when building a docker image e.g: docker/mailerlite/Dockerfile "defaults too Dockerfile"

**docker_tag** - if specified will allow you to override using the default git tag.

**docker_build_extra** - if specified will add docker build extra commands (see example).

**artifact_registry** - The artifact_registry to setup auth against e.g: us-east1-docker.pkg.dev (see example)

**helm_app_version** - if set to true, will update Helm chart appVersion to the current tag

**helm_pat** - The personal access token for setting up helm repository

# Examples
Running skaffold to deploy in the project?

``` yaml
- uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "europe-west1"
    cluster: "mailerlite-v2"
    skaffold_profile: "staging"
```

Just building a docker image? The version will be grabbed from the last tag (make sure this is something like v1.0.1 etc)
``` yaml
- uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "ZONE"
    docker_slug: "DOCKER_SLUG"
    docker_file: "Dockerfile"
```

Override git tag (can list with commas)
``` yaml
- uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "ZONE"
    docker_slug: "DOCKER_SLUG"
    docker_file: "Dockerfile"
    docker_tag: "v1.0.2,v1"
```

Add docker extra args for GitHub token etc
``` yaml
- uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "ZONE"
    docker_slug: "DOCKER_SLUG"
    docker_file: "Dockerfile"
    docker_build_extra: "--build-arg GITHUB_TOKEN=${{ secrets.GITHUBTOKEN }}"
```

Use Helm Repo
``` yaml
- uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "ZONE"
    cluster: "CLUSTER_NAME"
    skaffold_profile: "staging"
    helm_app_version: "true"
    helm_pat: ${{ secrets.HELM_PAT }}
```

Use different artifact registry
``` yaml
- uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "ZONE"
    cluster: "CLUSTER_NAME"
    skaffold_profile: "staging"
    artifact_registry: "us-east1-docker.pkg.dev"
```

Add docker extra args for multi Arch build extra steps needed
``` yaml
- name: Set up QEMU
  uses: docker/setup-qemu-action@master
  with:
    platforms: all

- name: Set up Docker Buildx
  id: buildx
  uses: docker/setup-buildx-action@master
  with:
    install: true

- name: Build and Push
  uses: mailergroup/gcloud-setup-deploy-action@v1.2.0
  with:
    service_account_key: ${{ secrets.GOOGLE_SERVICE_KEY }}
    project: "mailergroup"
    zone: "ZONE"
    docker_slug: "DOCKER_SLUG"
    docker_file: "Dockerfile"
    artifact_registry: "europe-docker.pkg.dev"
    docker_build_extra: "--platform linux/amd64,linux/arm64"
```
