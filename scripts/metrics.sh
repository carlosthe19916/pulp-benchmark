#!/usr/bin/env bash
#
# Reads the pulp-api autoscaler metric (and CPU/memory) from the stage cluster's Thanos.
# One script, two modes:
#
#   ./metrics.sh watch            Print time / avg-per-pod / busiest / pods every 15s.
#                                 Run this in a SECOND terminal to watch load climb live.
#
#   ./metrics.sh capture <dir>    Append <dir>/server-metrics.csv (one row every 15s) until
#                                 stopped. run-test.sh starts this in the background so the load
#                                 can be lined up against the autoscaler signal afterwards.
#
# "avg/pod" is the exact number the autoscaler watches. Its threshold is 4: when avg/pod goes
# above 4, the autoscaler would add pods.
#
set -euo pipefail

MODE="${1:-watch}"
THANOS_URL="https://thanos-querier.pulps01ue1.devshift.net/api/v1/query"
INTERVAL_SECONDS=15

# Only pulp-api's pods, in the stage namespace (used by the CPU/memory queries in capture mode).
SELECTOR='{namespace="pulp-stage",pod=~"pulp-api-.*",container="pulp-api"}'

# The PromQL, defined once and shared by both modes.
Q_AVG='avg(sum by (pod)(pulp_api_active_connections))'      # the autoscaler signal (avg/pod)
Q_BUSIEST='max(sum by (pod)(pulp_api_active_connections))'  # the busiest single pod
Q_PODS='count(count by (pod)(pulp_api_active_connections))' # number of pods
Q_CPU_AVG="avg(rate(container_cpu_usage_seconds_total${SELECTOR}[1m]))"
Q_CPU_MAX="max(rate(container_cpu_usage_seconds_total${SELECTOR}[1m]))"
Q_MEM_AVG="avg(container_memory_working_set_bytes${SELECTOR})/1024/1024"
Q_MEM_MAX="max(container_memory_working_set_bytes${SELECTOR})/1024/1024"

# --- shared setup: make sure we're on stage, then grab a short-lived read token ------------
# Use whatever cluster you're currently logged in to; refuse anything that isn't stage.
if ! oc whoami --show-server 2>/dev/null | grep -q pulps01ue1; then
  echo "Not logged in to the stage cluster. Run: oc login <pulps01ue1 ...>" >&2
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
  capture) capture_loop "${2:?usage: metrics.sh capture <output-dir>}" ;;
  *)       echo "usage: metrics.sh [watch | capture <output-dir>]" >&2; exit 1 ;;
esac
