# pulp-benchmark

Load tests for **pulp**. [k6](https://k6.io) generates traffic while, alongside it, the autoscaler metric
`pulp_api_active_connections` (plus CPU/memory)
is read from Thanos — to see how the app behaves under load and calibrate the KEDA autoscaler. The cluster is only ever
**read**, never modified.

## Setup

Requirements:
- [K6](https://grafana.com/docs/k6/latest/set-up/install-k6/)
- `oc login` (optional): login into the cluster `pulps01ue1` (Stage)
- Have a valid TBR:
  - https://access.stage.redhat.com/terms-based-registry/ (Stage)
  - Setup your username and password in [.env](.env) or:

```bash
cp .env .env.local     # add PULP_USER/PULP_PASS
```

## Load vs Stress

Two profiles, same requests — only the traffic ramp differs:

- **Load** ([`load-test.ts`](k6-scripts/load-test.ts)) ramps *to* expected peak and holds.
  Answers: *do we meet SLOs at normal traffic, and is the autoscaler calibrated right?*
- **Stress** ([`stress-test.ts`](k6-scripts/stress-test.ts)) ramps *past* saturation until it
  breaks. Answers: *where's the ceiling, and how does it fail?*

Run either profile against either endpoint via `make` (the target is `<profile>-<endpoint>`):

```bash
## Load tests
make load-status         # "/api/pulp/api/v3/status/"
make load-repositories   # "/api/pulp/default/api/v3/repositories/"

## Stress tests
make stress-status       # "/api/pulp/api/v3/status/"
make stress-repositories # "/api/pulp/default/api/v3/repositories/"
```

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

- **Ramps:** the `RAMPS` map in each profile script — `k6-scripts/load-test.ts` and
  `k6-scripts/stress-test.ts` (`{ target, duration }` per endpoint).
- **Endpoints:** the `ENDPOINTS` map in `k6-scripts/common.ts` (path + auth, type-checked), shared
  by both profiles. Adding one there also requires ramps for it in *both* scripts' `RAMPS`, or `tsc` fails.

The k6 scripts are **TypeScript** — k6 runs them natively, no build step. For editor IntelliSense and type-checking,
`npm install` once, then `make typecheck` (or `npx tsc --noEmit`). k6 itself needs none of this.

> Runs save raw data only; turning it into a report comes later, once the core is settled.

## Docs

- [`docs/architecture.md`](docs/architecture.md) — how the repo is laid out and how the pieces compose.
