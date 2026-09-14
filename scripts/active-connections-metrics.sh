#!/usr/bin/env bash
#
# Reads an autoscaler active_connections metric (and CPU/memory) from the stage cluster's Thanos.
# $METRIC/$SELECTOR pick the app (pulp-api or pulp-content); the defaults live in the Makefile.
# One script, two modes:
#
#   make watch                    Print time / avg-per-pod / busiest / pods every $INTERVAL_SECONDS.
#                                 Run this in a SECOND terminal to watch load climb live.
#
#   active-connections-metrics.sh capture <dir>
#                                 Append <dir>/server-metrics.csv (one row per interval) until
#                                 stopped. run-test.sh starts this in the background so the load
#                                 can be lined up against the autoscaler signal afterwards.
#
# "avg/pod" is the exact number the autoscaler watches. Its threshold is 4: when avg/pod goes
# above 4, the autoscaler would add pods.
#
# Config comes from the environment -- the defaults live in the Makefile (and nowhere else),
# which exports them. Run via `make watch`, or set the vars yourself for a direct run:
#   CLUSTER, THANOS_URL, METRIC, SELECTOR, INTERVAL_SECONDS
#
set -euo pipefail

: "${CLUSTER:?CLUSTER is not set -- run via the Makefile (make watch) or export it}"
: "${THANOS_URL:?THANOS_URL is not set -- run via the Makefile or export it}"
: "${METRIC:?METRIC is not set -- run via the Makefile or export it}"
: "${SELECTOR:?SELECTOR is not set -- run via the Makefile or export it}"
: "${INTERVAL_SECONDS:?INTERVAL_SECONDS is not set -- run via the Makefile or export it}"

MODE="${1:-watch}"

# The PromQL, built from $METRIC/$SELECTOR and shared by both modes.
Q_AVG="avg(sum by (pod)(${METRIC}))"      # the autoscaler signal (avg/pod)
Q_BUSIEST="max(sum by (pod)(${METRIC}))"  # the busiest single pod
Q_PODS="count(count by (pod)(${METRIC}))" # number of pods
Q_CPU_AVG="avg(rate(container_cpu_usage_seconds_total${SELECTOR}[1m]))"
Q_CPU_MAX="max(rate(container_cpu_usage_seconds_total${SELECTOR}[1m]))"
Q_MEM_AVG="avg(container_memory_working_set_bytes${SELECTOR})/1024/1024"
Q_MEM_MAX="max(container_memory_working_set_bytes${SELECTOR})/1024/1024"

# --- shared setup: make sure we're on stage, then grab a short-lived read token ------------
# Use whatever cluster you're currently logged in to; refuse anything that isn't $CLUSTER.
if ! oc whoami --show-server 2>/dev/null | grep -q "$CLUSTER"; then
  echo "Not logged in to the stage cluster. Run: oc login <$CLUSTER ...>" >&2
  exit 1
fi
TOKEN="$(oc whoami -t)"

# Run one Prometheus query and return its first value (0 if there's no data).
query() {
  local v
  v="$(curl --silent --insecure --get "$THANOS_URL" \
        --header "Authorization: Bearer $TOKEN" \
        --data-urlencode "query=$1" \
      | jq -r '.data.result[0].value[1] // "-"')"
  [[ "$v" == "-" ]] && echo 0 || echo "$v"
}

# --- mode: watch (human-readable live dashboard) -------------------------------------------
watch_loop() {
  printf "%-10s  %-9s  %-9s  %-5s\n" "time" "avg/pod" "busiest" "pods"
  while true; do
    avg=$(query     "$Q_AVG")
    busiest=$(query "$Q_BUSIEST")
    pods=$(query    "$Q_PODS")
    printf "%-10s  %-9s  %-9s  %-5s\n" "$(date +%H:%M:%S)" "$avg" "$busiest" "$pods"
    sleep "$INTERVAL_SECONDS"
  done
}

# --- mode: capture (machine-readable CSV, saved alongside the run) -------------------------
capture_loop() {
  local out_dir="$1" csv start elapsed
  csv="${out_dir}/server-metrics.csv"
  mkdir -p "$out_dir"
  echo "timestamp,elapsed_s,avg_per_pod,busiest,cpu_avg_cores,cpu_max_cores,mem_avg_mib,mem_max_mib,pods" > "$csv"

  start=$(date +%s)
  while true; do
    avg=$(query     "$Q_AVG")
    busiest=$(query "$Q_BUSIEST")
    cpu_avg=$(query "$Q_CPU_AVG")
    cpu_max=$(query "$Q_CPU_MAX")
    mem_avg=$(query "$Q_MEM_AVG")
    mem_max=$(query "$Q_MEM_MAX")
    pods=$(query    "$Q_PODS")

    elapsed=$(( $(date +%s) - start ))
    printf '%s,%s,%.2f,%.0f,%.3f,%.3f,%.0f,%.0f,%.0f\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$elapsed" \
      "$avg" "$busiest" "$cpu_avg" "$cpu_max" "$mem_avg" "$mem_max" "$pods" >> "$csv"
    sleep "$INTERVAL_SECONDS"
  done
}

case "$MODE" in
  watch)   watch_loop ;;
  capture) capture_loop "${2:?usage: active-connections-metrics.sh capture <output-dir>}" ;;
  *)       echo "usage: active-connections-metrics.sh [watch | capture <output-dir>]" >&2; exit 1 ;;
esac
