// Shared pieces for the pulp-api k6 scripts. There are two, and they differ ONLY in the shape
// of their ramp:
//   load-test.ts    -- ramp TO expected peak and hold      ("do we meet SLOs at normal traffic?")
//   stress-test.ts  -- ramp PAST peak until it breaks      ("where's the ceiling and how does it fail?")
// Both send the SAME request to the SAME endpoints, so everything they have in common lives here:
// the endpoint catalog, config parsing, the ramp lookup, and the per-VU request.
//
// How it works: each k6 "virtual user" (VU) sends one request, waits for the reply, then
// immediately sends the next. So at any moment there are ~VUs requests in flight -- which is
// exactly what `pulp_api_active_connections` counts. Run a test while watching the metric
// (run `make watch`) and you'll see it track the number of VUs.
//
// Config comes from environment variables (run-test.sh loads them from the repo's .env.local /
// .env, or your shell, so the password never lives in this file):
//   BASE_URL   e.g. https://packages.stage.redhat.com
//   ENDPOINT   "status" (light, no auth) or "repositories" (heavy DB query, needs auth)
//   PULP_USER, PULP_PASS   credentials for the authenticated endpoints

import http from "k6/http";
import { check } from "k6";
import encoding from "k6/encoding";

// The endpoints we can hit -- the single, type-checked source of truth for path + auth.
// `satisfies` enforces each entry's shape while keeping the literal keys, so the endpoint
// names flow into EndpointName below and each script's RAMPS is checked against them at compile time.
interface Endpoint {
  path: string;
  needsAuth: boolean;
}
const ENDPOINTS = {
  status:       { path: "/api/pulp/api/v3/status/",               needsAuth: false },
  repositories: { path: "/api/pulp/default/api/v3/repositories/", needsAuth: true  },
} satisfies Record<string, Endpoint>;

export type EndpointName = keyof typeof ENDPOINTS;
export type Stage = { target: number; duration: string };

// Pick the endpoint with the ENDPOINT env var (default: status), and resolve its URL + headers once.
const endpointName = (__ENV.ENDPOINT || "status") as EndpointName;
const endpoint = ENDPOINTS[endpointName];
if (!endpoint) {
  throw new Error(`Unknown ENDPOINT "${endpointName}"; valid: ${Object.keys(ENDPOINTS).join(", ")}`);
}
const targetUrl = `${__ENV.BASE_URL}${endpoint.path}`;

// Build the request headers once. Only add Basic auth when the endpoint requires it.
const headers: Record<string, string> = endpoint.needsAuth
  ? { Authorization: "Basic " + encoding.b64encode(`${__ENV.PULP_USER}:${__ENV.PULP_PASS}`) }
  : {};

// Resolve the ramp for the selected endpoint from a script's per-endpoint RAMPS map. Each script
// must define a ramp for every endpoint (the `satisfies` there enforces it), so a miss is a bug.
export function stagesFor(ramps: Record<EndpointName, Stage[]>): Stage[] {
  const stages = ramps[endpointName];
  if (!stages) {
    throw new Error(`No ramp for ENDPOINT "${endpointName}"`);
  }
  return stages;
}

// What each virtual user does, over and over: one GET, check it returned 200. Both scripts use
// this as their default export -- the ramp is the only thing that changes between them.
export function request(): void {
  const response = http.get(targetUrl, { headers, timeout: "60s" });
  check(response, { "status is 200": (r) => r.status === 200 });
}
