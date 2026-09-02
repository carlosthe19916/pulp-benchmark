#!/usr/bin/env bash
#
# Produces the raw data for ONE load-test run.
#
# Config (BASE_URL, PULP_USER, PULP_PASS) comes from the repo's own .env files -- no external
# directories. Precedence: your shell environment wins, then .env.local (gitignored, your real
# values), then .env (committed defaults, no secrets). Only k6 is required; if you are also
# logged in to the stage cluster it records the server-side metrics from Thanos alongside k6.
# Everything lands in $OUT_DIR (results/<time>_<endpoint>_<profile>/ by default):
#   run-info.json        what was tested (endpoint, profile, target, time)
#   k6-summary.json      k6's client-side headline numbers (RPS, latency, errors)
#   k6-timeseries.csv    k6's client-side metrics over time (raw --out csv stream)
#   server-metrics.csv   avg/pod signal + CPU/memory over time (only if logged in to stage)
#
# Prefer the Makefile front door (make status-load, make repos-stress, ...); those targets
# inject OUT_DIR. You can also run it directly with env vars:
#   ./run-test.sh                                     # load test, "status" endpoint (default)
#   ENDPOINT=repositories ./run-test.sh               # heavy DB endpoint (careful: shared stage DB)
#   PROFILE=stress ENDPOINT=status ./run-test.sh      # stress test
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load KEY=value lines from an env file WITHOUT clobbering anything already set. Because we load
# .env.local before .env, and skip keys already in the environment, precedence is:
# shell environment > .env.local > .env.
load_env() {
  local file="$1" key value
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r key value; do
    key="${key%%[[:space:]]*}"                 # trim, and drop blank / commented lines
    [[ -z "$key" || "$key" == \#* ]] && continue
    [[ -n "${!key:-}" ]] && continue           # already set (shell env or an earlier file) -> keep it
    value="${value#\"}"; value="${value%\"}"   # strip optional surrounding quotes
    export "$key=$value"
  done < "$file"
}
load_env "$SCRIPT_DIR/.env.local"
load_env "$SCRIPT_DIR/.env"

# Give k6 what it needs via the environment (see load-test.ts).
export BASE_URL PULP_USER PULP_PASS
export ENDPOINT="${ENDPOINT:-status}"
export PROFILE="${PROFILE:-load}"   # "load" (default) or "stress"

: "${BASE_URL:?BASE_URL is not set -- add it to .env.local (cp .env .env.local) or export it}"

# One folder per run, named so runs are easy to tell apart and compare. The Makefile injects
# OUT_DIR; we default it for direct runs.
STAMP="$(date -u +%Y-%m-%dT%H-%M)"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/results/${STAMP}_${ENDPOINT}_${PROFILE}}"
mkdir -p "$OUT_DIR"

# Record what this run was. No credentials -- just what was tested.
# The endpoint path lives in the k6 script (load-test.ts), so we record the endpoint name here.
cat > "${OUT_DIR}/run-info.json" <<EOF
{"endpoint": "${ENDPOINT}", "profile": "${PROFILE}", "base_url": "${BASE_URL}", "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

echo "Load testing ${BASE_URL} (endpoint: ${ENDPOINT}, profile: ${PROFILE})"
echo "Results -> ${OUT_DIR}"
echo "Tip: run 'make watch' in another terminal to watch the metric live."
echo

# Server-side metrics are OPTIONAL: only capture them when we can reach the stage cluster.
# Without oc/login the load test still runs -- you just get k6's client-side numbers.
CAPTURE_PID=""
if command -v oc >/dev/null && oc whoami --show-server 2>/dev/null | grep -q pulps01ue1; then
  "${SCRIPT_DIR}/scripts/metrics.sh" capture "$OUT_DIR" &
  CAPTURE_PID=$!
  # Always stop the recorder, even if k6 fails or we're interrupted.
  trap 'kill "$CAPTURE_PID" 2>/dev/null || true' EXIT
else
  echo "Note: not logged in to the stage cluster -- skipping server metrics (k6 client-side only)."
  echo
fi

k6 run --summary-export="${OUT_DIR}/k6-summary.json" \
       --out csv="${OUT_DIR}/k6-timeseries.csv" \
       "${SCRIPT_DIR}/k6-scripts/load-test.ts"

[[ -n "$CAPTURE_PID" ]] && kill "$CAPTURE_PID" 2>/dev/null || true
trap - EXIT

echo "Raw data saved to ${OUT_DIR}"
