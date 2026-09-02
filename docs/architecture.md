# Architecture

How the repo is laid out and how the pieces compose. Each piece does one job; the Makefile
chains them.

## Layout

```
Makefile          front door (make help). Picks the run folder and calls run-test.sh
run-test.sh       produces one run's raw data (run-info + k6 + server metrics)
scripts/
  metrics.sh      read metrics from Thanos (watch = live, capture = CSV)
k6-scripts/
  common.ts       shared k6 code (TypeScript): the ENDPOINTS, config, and the request
  load-test.ts    load profile: ramp TO expected peak and hold (its own RAMPS)
  stress-test.ts  stress profile: ramp PAST saturation until it breaks (its own RAMPS)
.env              committed config template (no secrets); copy to .env.local
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
   └─ run_benchmark (Makefile): pick RUN_DIR, then run the test
        └─ run-test.sh  ──►  RUN_DIR/  (run-info.json, k6-*.json/csv, server-metrics.csv)
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
| `server-metrics.csv` | metrics.sh (capture) | server-side time series (only if logged in to stage) |

## Single sources of truth

- **Endpoints** (path + auth) live only in the `ENDPOINTS` map in `common.ts`, as a type-checked
  object shared by both profiles — `run-test.sh` passes the endpoint *name*, the script owns the path.
- **Ramps** (`{ target, duration }` per endpoint) live only in each profile's own `RAMPS` map —
  `load-test.ts` for load, `stress-test.ts` for stress.
- **Config** (`BASE_URL`, `PULP_USER`, `PULP_PASS`) comes from `.env.local` → `.env`, with the
  shell environment overriding both. Precedence: **shell env > `.env.local` > `.env`**.
- **PromQL** for the autoscaler signal + CPU/memory is defined once at the top of `metrics.sh`
  and shared by both its `watch` and `capture` modes.

## Requirements: only k6 is mandatory

Everything else is optional and the run degrades gracefully.

| Tool | Status | Without it |
|---|---|---|
| k6 | required | nothing runs |
| `oc` + stage login | optional | no `server-metrics.csv`; k6 client-side data only |
| `PULP_USER` / `PULP_PASS` | optional | use the `status` endpoint (no auth) |
| jq | optional | only used by the (optional) metrics capture |
