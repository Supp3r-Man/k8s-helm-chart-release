# k8s-helm-chart-release

![ci](https://github.com/Supp3r-Man/k8s-helm-chart-release/actions/workflows/ci.yml/badge.svg)

A Helm chart with the pipeline around it: strict lint, schema validation, `values.schema.json` negative tests, chart-testing on a kind cluster, an install-upgrade-rollback test, and a release that publishes the chart as an **OCI artifact on GHCR** and then installs *that artifact*.

> **What is verified.** On 2026-10-17 all of this ran green on GitHub Actions: `lint`, `install` (chart-testing) and `upgrade`; then pushing the tag `v0.1.0` ran `release`, whose `publish` and `verify` jobs both succeeded. The published chart is `oci://ghcr.io/supp3r-man/charts/webapp` version `0.1.0` (digest `sha256:752727ae...`). I did not run helm locally.

## The chart (`charts/webapp`)

An nginx service that serves a configurable `message`: Deployment (non-root, read-only root filesystem, dropped capabilities, probes, `maxUnavailable: 0`), Service, ConfigMap, ServiceAccount, optional PodDisruptionBudget and HorizontalPodAutoscaler, a `helm test` pod, and a `values.schema.json`. A **checksum annotation** on the pod template means changing `message` (a ConfigMap change) rolls the pods; without it Helm would update the ConfigMap and leave the old pods running.

## The pipeline

| Job | What it does | Result |
|---|---|---|
| `lint` | `helm lint --strict` for the defaults and each `ci/*.yaml`; `helm template` into kubeconform (strict, Kubernetes 1.33) for each; `scripts/schema-tests.sh`; shellcheck | green |
| schema tests | 6 bad values must be **rejected** (`replicaCount` 0, 100 or a string; `pullPolicy=Sometimes`; port 70000; `service.type=ExternalName`) and 1 good combination accepted | 7 of 7 |
| `install` | chart-testing: `ct lint`, then `ct install` once per `ci/` values file (defaults, custom message, autoscaling), each followed by `helm test` | green |
| `upgrade` | install with message one, `helm test`, upgrade to message two, check the served message and revision, `helm rollback 1`, check message one is back and the revision is 3 | 6 of 6 |
| `release` (on a `v*` tag) | refuses if the tag does not match `Chart.yaml`'s version; `helm package`, `helm push` to GHCR; then, in a separate job, installs the **published** chart from the registry and runs the same upgrade-and-rollback test | green, 6 of 6 |

Why install the published artifact: it proves what users will actually get, not what is in the source tree (a missing file in the package would pass every earlier job).

## Honest limits

- **Package visibility not checked.** A package created by a workflow on GHCR is usually private; my token cannot read package settings, so I do not know whether `helm pull` works anonymously. The `verify` job authenticates with the workflow token.
- **The upgrade test is not an upgrade from a previous release.** It upgrades between two *values* of the same chart version. There was no earlier release to upgrade from until `0.1.0` existed; the next release is when a real previous-version upgrade can be added.
- `ct.yaml` turns off the version-increment and maintainers checks (single chart, no history, no maintainers listed). A real chart repo would turn them on.
- The chart is **not signed** (no cosign or provenance file); see `k8s-supply-chain-gate` for signing.
- The HPA is rendered and installed but cannot act: kind has no metrics-server.
- Helm itself is the latest version `azure/setup-helm` installs, not pinned; kind node versions come from `helm/kind-action`'s default.
- **A flaky check I found by running it twice.** On the copy of this repo in a second GitHub account, the first request from the throwaway probe pod returned nothing (the pod was still pulling its image) and failed 1 of 6 checks, although the same run on the first account had passed. `served_message` now retries. One green run is weaker evidence than it looks.
- It publishes a chart only; there is no GitHub Pages index or release notes.

## Release a new version

Bump `version` in `charts/webapp/Chart.yaml`, merge, then `git tag vX.Y.Z && git push origin vX.Y.Z`.

## Use the published chart

```
helm install demo oci://ghcr.io/supp3r-man/charts/webapp --version 0.1.0 --set message="hello"
```

(This requires the package to be readable by you; see the visibility note above.)
