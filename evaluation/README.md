# Manual pilot

Use the existing mailerlite dev branch build/deploy path. Include native amd64 and
arm64 builds, the manifest-merge job and deployment. Preserve the application
commit, runner labels/resources, build-cache settings and operations between variants.
Use scratch image tags and a dev namespace, and serialize conflicting operations.

Before timing runs, record the Docker workflow SHA/image digest, candidate released
action SHA, pilot workflow SHA, cluster versions, runner details and acceptable
whole-job time regression. Confirm build/push, registry login, GKE access, deploy,
secret decryption and cleanup work. Add a Helm diff check if the selected path uses it.
No authenticated tests or timing runs have been recorded yet.

Run five Docker/Nix pairs, alternating order. Use fresh runners and note image-layer
and public binary cache conditions. Record each job separately. Add more runs only
if results are noisy, close or failures need investigation.

| Pair | Variant | Job / architecture | Run link | Setup | Job start to finish | Result / retries / cache notes |
|---|---|---|---|---|---|---|

Copy timings manually from GitHub Actions; exclude queue wait. Setup means container
initialization for Docker and the full setup action for Nix. Whole-job duration is
primary. Report successes/attempts and median/range for successful runs; keep failed
runs and their timings visible separately.

Restore the pinned Docker baseline and confirm recovery. Try one tool update and
one addition in each approach, noting rough hands-on effort and practical problems.
Write a short recommendation with limitations: adopt in stages, investigate a specific
question, or retain Docker. Review with SRE and the manager. No private cache,
benchmark service or broad consumer migration is part of this pilot.
