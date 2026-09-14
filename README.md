# pulp-benchmark

Load tests for **pulp-api** and **pulp-content**. [k6](https://k6.io) generates traffic while, alongside it, the
autoscaler metric (`pulp_api_active_connections` or `pulp_content_active_connections`, plus CPU/memory)
is read from Thanos — to see how the app behaves under load and calibrate the KEDA autoscaler. The cluster is only ever
**read**, never modified.

## Setup

Requirements:
- [K6](https://grafana.com/docs/k6/latest/set-up/install-k6/)
- `oc login` (optional): login into the cluster `pulps01ue1` (Stage)
- Have a valid TBR:
  - https://access.stage.redhat.com/terms-based-registry/ (Stage)

## Load vs Stress

Two profiles, same requests — only the traffic ramp differs:

- **Load** ([`load-test.ts`](k6-scripts/load-test.ts)) ramps *to* expected peak and holds.
  Answers: *do we meet SLOs at normal traffic, and is the autoscaler calibrated right?*
- **Stress** ([`stress-test.ts`](k6-scripts/stress-test.ts)) ramps *past* saturation until it
  breaks. Answers: *where's the ceiling, and how does it fail?*

Run either profile against either endpoint via `make` (the target is `<profile>-<endpoint>`):

```bash
## pulp-api  (watch alongside with: make watch)
make load-status         # "/api/pulp/api/v3/status/"          (no auth)
make load-repositories   # "/api/pulp/default/api/v3/repositories/"
make stress-status
make stress-repositories

## pulp-content  (watch alongside with: make watch-content)
make load-content-file   # fetch a package  -> 302 redirect to object storage
make load-content-index  # fetch a PyPI index -> 200 HTML pulp-content generates
make stress-content-file
make stress-content-index
```

pulp-content (a separate app) has two response modes, one per endpoint. **content-file** requests a
package and pulp-content **redirects (302)** to object storage — that redirect is the work we
measure, so it counts the 302 as success and does not follow it. **content-index** requests a PyPI
simple index and pulp-content generates and streams the HTML itself (**200**). Both endpoints, like
`repositories`, need `PULP_USER`/`PULP_PASS`; their fetched paths live in `k6-scripts/common.ts`.

## Results

Each run writes its own folder, `results/<time>_<endpoint>_<profile>/`:

```
run-info.json      what was tested (endpoint, profile, base_url, started_at)
k6-summary.json    k6 headline numbers (RPS, latency percentiles, error rate)
k6-timeseries.csv  k6's raw per-sample stream (for Grafana/spreadsheets)
server-metrics.csv one row per ~15s: avg/pod, busiest, CPU/mem avg+max, pods
                   (only when logged in to stage)
```

## How to read it

- Each k6 **VU** keeps one request in flight, so **VUs ≈ concurrent requests**.
- **avg/pod** is the exact signal the autoscaler watches; above **4** it would add pods.
- Little's Law: `avg/pod ≈ requests_in_flight / pods`. On `status` it tops out near **5/pod** — the 5 gunicorn workers
  per pod.

## Customize

- **Ramps:** the `stages` array in each profile script — `k6-scripts/load-test.ts` and
  `k6-scripts/stress-test.ts` (one ramp per profile, applied to whichever endpoint runs).
- **Endpoints:** the `ALL_ENDPOINTS` map in `k6-scripts/common.ts` (path + auth, type-checked),
  shared by both profiles.

The k6 scripts are **TypeScript** — k6 runs them natively, no build step. For editor IntelliSense and type-checking,
`npm install` once, then `make typecheck` (or `npx tsc --noEmit`). k6 itself needs none of this.

> Runs save raw data only; turning it into a report comes later, once the core is settled.

## Docs

- [`docs/architecture.md`](docs/architecture.md) — how the repo is laid out and how the pieces compose.
