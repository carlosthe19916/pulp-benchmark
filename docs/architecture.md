# Architecture

How the repo is laid out and how the pieces compose. Each piece does one job; the Makefile
chains them.

## Layout

```
Makefile          front door (make help) AND the single home for all config defaults, which it
                  exports to the scripts below; calls run-test.sh
run-test.sh       produces one run's raw data (run-info + k6 + server metrics)
scripts/
  active-connections-metrics.sh
                  read pulp_api_active_connections (+ CPU/memory) from Thanos (watch = live, capture = CSV)
k6-scripts/
  common.ts       shared k6 code (TypeScript): the ENDPOINTS, config, and the request
  load-test.ts    load profile: ramp TO expected peak and hold (its own RAMPS)
  stress-test.ts  stress profile: ramp PAST saturation until it breaks (its own RAMPS)
tsconfig.json     TypeScript config for editor type-checking (make typecheck)
package.json      dev-only: pulls in @types/k6 (not needed to run k6)
results/          one folder per run (gitignored)
docs/             this design doc + recorded findings
```

The scripts are TypeScript; k6 v0.57+ runs `.ts` natively (esbuild strips types — it does not
type-check). Type safety comes from your editor / `make typecheck` via `@types/k6`. k6 requires
the `.ts` extension on local imports (e.g. `from "./common.ts"`), so `tsconfig.json` enables
`allowImportingTsExtensions`.

Load and stress are **two scripts, one shared core**: `common.ts` owns the endpoints, config, and
the request; each profile script owns only its `RAMPS` and `options`. `run-test.sh` maps
`PROFILE` (load | stress) to the script it runs.

## A run

A benchmark produces raw data, nothing more. The Makefile picks a per-run folder and calls
`run-test.sh`, which runs k6 and — if you're logged in to stage — captures the server-side
metrics alongside it.

```
make load-status
   └─ run_benchmark (Makefile): set ENDPOINT/PROFILE, then run the test
        └─ run-test.sh  ──►  results/<time>_<endpoint>_<profile>/
                             (run-info.json, k6-*.json/csv, server-metrics.csv)
```

Turning that raw data into a rendered report is deliberately left out for now — it's a separate
step to add once the core (traffic generation + metric capture) is settled.

## Data contract (`results/<run>/`)

Each run folder holds the raw artifacts. Files and their producers:

| File | Produced by | What it is |
|---|---|---|
| `run-info.json` | run-test.sh | what was tested (endpoint, profile, base_url, time) |
| `k6-summary.json` | k6 (via run-test.sh) | k6 client-side headline numbers |
| `k6-timeseries.csv` | k6 (via run-test.sh) | k6's raw per-sample stream (Grafana/spreadsheets) |
| `server-metrics.csv` | active-connections-metrics.sh (capture) | server-side time series (only if logged in to stage) |

## Single sources of truth

- **Endpoints** (path + auth) live only in the `ENDPOINTS` map in `common.ts`, as a type-checked
  object shared by both profiles — `run-test.sh` passes the endpoint *name*, the script owns the path.
- **Ramps** (`{ target, duration }` per endpoint) live only in each profile's own `RAMPS` map —
  `load-test.ts` for load, `stress-test.ts` for stress.
- **Config** — every tunable (`BASE_URL`, credentials, `ENDPOINT`/`PROFILE`, and the server-metric
  settings `CLUSTER`, `THANOS_URL`, `SELECTOR`, `INTERVAL_SECONDS`) has its default in
  **one place, the `Makefile`** (`?=`), which `export`s them to the scripts. The scripts carry no
  defaults of their own — they read the environment and fail loudly if a required var is unset, so
  everything runs through `make`. Override any value from the shell or command line; an existing
  environment value wins over the Makefile default. Credentials have no default and are never
  committed — pass `PULP_USER`/`PULP_PASS` via the environment.
- **The stage guard** (`oc whoami --show-server | grep -q "$CLUSTER"`) decides whether server
  metrics are captured; it lives inline in both `run-test.sh` and `active-connections-metrics.sh`,
  driven by the `CLUSTER` env var.
- **PromQL** for the autoscaler signal + CPU/memory is built once at the top of
  `active-connections-metrics.sh` from `SELECTOR` and the hardcoded `pulp_api_active_connections`
  metric, and shared by both its `watch` and `capture` modes.

## Requirements: only k6 is mandatory

Everything else is optional and the run degrades gracefully.

| Tool | Status | Without it |
|---|---|---|
| k6 | required | nothing runs |
| `oc` + stage login | optional | no `server-metrics.csv`; k6 client-side data only |
| `PULP_USER` / `PULP_PASS` | optional | use the `status` endpoint (no auth) |
| jq | optional | only used by the (optional) metrics capture |
