#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

: "${BASE_URL:?BASE_URL is not set -- run via the Makefile (make load-status) or export it}"
: "${ENDPOINT:?ENDPOINT is not set -- run via the Makefile or export it (e.g. status)}"
: "${PROFILE:?PROFILE is not set -- run via the Makefile or export it (load | stress)}"

# The profile picks WHICH k6 script runs -- each owns its own ramp (see k6-scripts/*-test.ts).
case "$PROFILE" in
  load)   SCRIPT="load-test.ts" ;;
  stress) SCRIPT="stress-test.ts" ;;
  *) echo "Unknown PROFILE \"$PROFILE\" -- valid: load, stress" >&2; exit 1 ;;
esac

# One folder per run, named so runs are easy to tell apart and compare.
STAMP="$(date -u +%Y-%m-%dT%H-%M)"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/results/${STAMP}_${ENDPOINT}_${PROFILE}}"
mkdir -p "$OUT_DIR"

# Record what this run was. No credentials -- just what was tested.
# The endpoint path lives in the k6 script (k6-scripts/common.ts), so we record the endpoint name here.
cat > "${OUT_DIR}/run-info.json" <<EOF
{"endpoint": "${ENDPOINT}", "profile": "${PROFILE}", "base_url": "${BASE_URL}", "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

echo "Running ${PROFILE} test against ${BASE_URL} (endpoint: ${ENDPOINT})"
echo "Results -> ${OUT_DIR}"
WATCH=watch; [[ "$ENDPOINT" == content* ]] && WATCH=watch-content
echo "Tip: run 'make ${WATCH}' in another terminal to watch the metric live."
echo

k6 run --summary-export="${OUT_DIR}/k6-summary.json" \
       --out csv="${OUT_DIR}/k6-timeseries.csv" \
       "${SCRIPT_DIR}/k6-scripts/${SCRIPT}"

echo "Raw data saved to ${OUT_DIR}"
