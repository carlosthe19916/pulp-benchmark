# pulp-benchmark

Load tests for **pulp-api** on the **stage** cluster. [k6](https://k6.io) generates traffic
locally while, alongside it, the autoscaler metric `pulp_api_active_connections` (plus CPU/memory)
is read from Thanos — to see how the app behaves under load and calibrate the KEDA autoscaler. The
cluster is only ever **read**, never modified.

## Setup

Only **k6** is required — with it on your PATH you can run a load test and get k6's client-side
numbers. Everything else is optional and the run degrades gracefully without it:

| Optional | Enables | Without it |
|---|---|---|
| `oc login` to stage (`pulps01ue1`) | server-side metrics (avg/pod, CPU, memory) | k6 client-side numbers only |
| `PULP_USER` / `PULP_PASS` | authenticated endpoints (`repositories`) | use `status` (no auth) |

Config loads from `.env.local` (gitignored — secrets stay local), falling back to the committed
`.env` (which already sets a default `BASE_URL`). Any shell variable overrides both — precedence:
**shell env > `.env.local` > `.env`**. To customize:

```bash
cp .env .env.local     # add PULP_USER/PULP_PASS (BASE_URL already points at stage)
make check             # shows what's present; only the [required] line must pass
```

## Run

```bash
make status-load     # load test the light "status" endpoint
make status-stress   # stress it past saturation
make repos-load      # load test the heavy "repositories" endpoint (shared stage DB — gentle)
make repos-stress    # stress the repositories endpoint

make watch           # live dashboard of avg/pod (run in a 2nd terminal)
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
- Little's Law: `avg/pod ≈ requests_in_flight / pods`. On `status` it tops out near **5/pod** —
  the 5 gunicorn workers per pod.

## Customize

- **Ramps:** the `RAMPS` map in `k6-scripts/load-test.ts` (`{ target, duration }` per endpoint/profile).
- **Endpoints:** the `ENDPOINTS` map at the top of `k6-scripts/load-test.ts` (path + auth,
  type-checked). Adding one there also requires ramps for it in `RAMPS`, or `tsc` fails.

The k6 script is **TypeScript** — k6 runs it natively, no build step. For editor IntelliSense and
type-checking, `npm install` once, then `make typecheck` (or `npx tsc --noEmit`). k6 itself needs
none of this.

> Runs save raw data only; turning it into a report comes later, once the core is settled.

## Docs

- [`docs/architecture.md`](docs/architecture.md) — how the repo is laid out and how the pieces compose.
