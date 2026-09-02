# pulp-benchmark -- front door for the load tests.
#
# Every test target just sets ENDPOINT/PROFILE and calls run-test.sh, which runs k6 locally
# against stage and records the server-side metrics from Thanos into results/.
#
# e.g. `make load-status` to load-test the status endpoint against stage.

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help watch typecheck

# --- Configuration: every default lives HERE and nowhere else ------------------------------
# The scripts (run-test.sh, scripts/metrics.sh) read these from the environment -- they carry no
# defaults of their own. Override any value from your shell (VAR=... make <target>) or on the
# command line (make <target> VAR=...); `?=` means an existing environment value always wins.
# (Comments stay on their own lines: Make keeps trailing whitespace before an inline `#`, which
# would silently corrupt values like the URLs below.)
#
# Credentials have NO default -- pass them the same way, e.g.
#   make load-repositories PULP_USER='...' PULP_PASS='...'
# (or `export` them first to keep the token out of your shell history).
#
# BASE_URL          base URL of the pulp API (required)
# PULP_USER/PASS    credentials for authenticated endpoints (e.g. repositories); blank for status
# CLUSTER           oc cluster name the stage guard matches against `oc whoami`
# THANOS_URL        Prometheus/Thanos query endpoint the metric reader curls
# SELECTOR          PromQL label selector for pulp-api's pods (CPU/memory queries)
# METRIC            the autoscaler signal metric name
# INTERVAL_SECONDS  how often scripts/metrics.sh samples Thanos
BASE_URL         ?= https://packages.stage.redhat.com
PULP_USER        ?=
PULP_PASS        ?=
CLUSTER          ?= pulps01ue1
THANOS_URL       ?= https://thanos-querier.pulps01ue1.devshift.net/api/v1/query
SELECTOR         ?= {namespace="pulp-stage",pod=~"pulp-api-.*",container="pulp-api"}
METRIC           ?= pulp_api_active_connections
INTERVAL_SECONDS ?= 15
export BASE_URL PULP_USER PULP_PASS CLUSTER THANOS_URL SELECTOR METRIC INTERVAL_SECONDS

# One benchmark = produce the raw data for a run. Needs only k6; run-test.sh does the work and
# owns the results/<time>_<endpoint>_<profile>/ folder naming. $(1) = endpoint, $(2) = profile.
define run_benchmark
	ENDPOINT=$(1) PROFILE=$(2) ./run-test.sh
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
