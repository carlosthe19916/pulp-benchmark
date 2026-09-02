# pulp-benchmark -- front door for the load tests.
#
# Every test target just sets ENDPOINT/PROFILE and calls run-test.sh, which runs k6 locally
# against stage and records the server-side metrics from Thanos into results/.
#
# Run `make check` first to confirm your prerequisites, then e.g. `make load-status`.

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

# Pattern rules: the profile is fixed by the target (load | stress) and the stem ($*) is the
# endpoint -- load-status, stress-status, load-repositories, stress-repositories. The profile
# maps to the matching k6 script inside run-test.sh; the endpoint's path lives in the k6 script.
load-%: ## Load-test an endpoint (load-status | load-repositories)
	@$(call run_benchmark,$*,load)

stress-%: ## Stress-test an endpoint, mind the shared stage DB for repositories (stress-status | stress-repositories)
	@$(call run_benchmark,$*,stress)

watch: ## Live dashboard of the autoscaler metric (run in a 2nd terminal)
	./scripts/metrics.sh watch

typecheck: ## Type-check the k6 TypeScript script (needs: npm install)
	npx tsc --noEmit
