# pulp-benchmark -- front door for the load tests.
#
# Every test target just sets ENDPOINT/PROFILE and calls run-test.sh, which runs k6 locally
# against stage and records the server-side metrics from Thanos into results/.
#
# Run `make check` first to confirm your prerequisites, then e.g. `make status-load`.

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help check watch typecheck clean

# One benchmark = produce the raw data for a run. Needs only k6; run-test.sh does the work.
# $(1) = endpoint, $(2) = profile.
define run_benchmark
	set -e; \
	RUN_DIR="results/$$(date -u +%Y-%m-%dT%H-%M)_$(1)_$(2)"; \
	ENDPOINT=$(1) PROFILE=$(2) OUT_DIR="$$RUN_DIR" ./run-test.sh
endef

help: ## Show this help
	@echo "pulp-benchmark -- load tests for the pulp-api autoscaler metric"
	@echo
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_%-]+:.*## ' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN{FS=":.*## "}{printf "  %-16s %s\n", $$1, $$2}'

check: ## Verify prerequisites (only k6 is required; the rest are optional)
	@command -v k6 >/dev/null \
	  && echo "ok  [required] k6 ($$(k6 version | head -1))" \
	  || echo "MISSING [required] k6 not on PATH -- nothing runs without it"
	@oc whoami --show-server 2>/dev/null | grep -q pulps01ue1 \
	  && echo "ok  [optional] logged in to stage ($$(oc whoami)) -- server metrics will be captured" \
	  || echo "--  [optional] not logged in to stage -- runs skip server metrics (k6 client-side only)"

# Pattern rules: the stem ($*) is the profile (load | stress). Same commands as before --
# status-load, status-stress, repos-load, repos-stress -- with half the definitions.
# An unknown profile falls through to k6, which errors with "No ramp for PROFILE ...".
status-%: ## Load/stress the light status endpoint (status-load | status-stress)
	@$(call run_benchmark,status,$*)

repos-%: ## Load/stress the heavy repositories endpoint, shared stage DB (repos-load | repos-stress)
	@$(call run_benchmark,repositories,$*)

watch: ## Live dashboard of the autoscaler metric (run in a 2nd terminal)
	./scripts/metrics.sh watch

typecheck: ## Type-check the k6 TypeScript script (needs: npm install)
	npx tsc --noEmit

clean: ## Remove all saved runs under results/ (keeps the folder)
	find results -mindepth 1 ! -name .gitkeep -exec rm -rf {} +
