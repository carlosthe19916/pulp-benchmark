.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help watch watch-content typecheck

# BASE_URL          base URL of the pulp API (required)
# PULP_USER/PULP_PASS    credentials for authenticated endpoints (repositories, content); blank for status
# CLUSTER           oc cluster name the stage guard matches against `oc whoami`
# THANOS_URL        Prometheus/Thanos query endpoint the metric reader curls
# METRIC/SELECTOR   effective autoscaler metric + PromQL pod selector the reader queries;
#                   default to the pulp-api preset below, overridden by watch-content
# INTERVAL_SECONDS  how often scripts/active-connections-metrics.sh samples Thanos
BASE_URL         ?= https://packages.stage.redhat.com
PULP_USER        ?=
PULP_PASS        ?=
CLUSTER          ?= pulps01ue1
THANOS_URL       ?= https://thanos-querier.pulps01ue1.devshift.net/api/v1/query
METRIC           ?= $(API_METRIC)
SELECTOR         ?= $(API_SELECTOR)
INTERVAL_SECONDS ?= 15
export BASE_URL PULP_USER PULP_PASS CLUSTER THANOS_URL METRIC SELECTOR INTERVAL_SECONDS

# Per-app presets: each app's autoscaler metric + pods. watch uses api, watch-content uses content.
API_METRIC       = pulp_api_active_connections
API_SELECTOR     = {namespace="pulp-stage",pod=~"pulp-api-.*",container="pulp-api"}
CONTENT_METRIC   = pulp_content_active_connections
CONTENT_SELECTOR = {namespace="pulp-stage",pod=~"pulp-content-.*",container="pulp-content"}

# One benchmark = produce the raw data for a run. Needs only k6; run-test.sh does the work and
# owns the results/<time>_<endpoint>_<profile>/ folder naming. $(1) = endpoint, $(2) = profile.
define run_benchmark
	ENDPOINT=$(1) PROFILE=$(2) ./run-test.sh
endef

help: ## Show this help
	@echo "pulp-benchmark -- load tests for the pulp-api and pulp-content autoscaler metrics"
	@echo
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_%-]+:.*## ' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN{FS=":.*## "}{printf "  %-16s %s\n", $$1, $$2}'

# Pattern rules: the profile is fixed by the target (load | stress) and the stem ($*) is the
# endpoint -- load-status, stress-status, load-repositories, load-content, ... The profile maps
# to the matching k6 script inside run-test.sh; the endpoint's path lives in the k6 script.
load-%: ## Load-test an endpoint (load-status | load-repositories | load-content-file | load-content-index)
	@$(call run_benchmark,$*,load)

stress-%: ## Stress-test an endpoint, mind the shared stage DB for repositories (stress-status | stress-repositories | stress-content-file | stress-content-index)
	@$(call run_benchmark,$*,stress)

watch: ## Live dashboard of the pulp-api autoscaler metric (run in a 2nd terminal)
	@METRIC=$(API_METRIC) SELECTOR='$(API_SELECTOR)' ./scripts/active-connections-metrics.sh watch

watch-content: ## Live dashboard of the pulp-content autoscaler metric (run in a 2nd terminal)
	@METRIC=$(CONTENT_METRIC) SELECTOR='$(CONTENT_SELECTOR)' ./scripts/active-connections-metrics.sh watch
