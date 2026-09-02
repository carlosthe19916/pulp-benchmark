// Load test for the pulp-api autoscaler metric `pulp_api_active_connections`.
//
// How it works: each k6 "virtual user" (VU) sends one request, waits for the reply, then
// immediately sends the next. So at any moment there are ~VUs requests in flight -- which is
// exactly what `pulp_api_active_connections` counts. Run this while watching the metric
// (run `make watch`) and you'll see the metric track the number of VUs.
//
// Config comes from environment variables (run-test.sh loads them from the repo's .env.local /
// .env, or your shell, so the password never lives in this file):
//   BASE_URL   e.g. https://packages.stage.redhat.com
//   ENDPOINT   "status" (light, no auth) or "repositories" (heavy DB query, needs auth)
//   PULP_USER, PULP_PASS   credentials for the authenticated endpoints

import http from "k6/http";
import { check } from "k6";
import encoding from "k6/encoding";
import { Options } from "k6/options";

// The endpoints we can hit -- the single, type-checked source of truth for path + auth.
// `satisfies` enforces each entry's shape while keeping the literal keys, so the endpoint
// names flow into EndpointName below and RAMPS is checked against them at compile time.
interface Endpoint {
  path: string;
  needsAuth: boolean;
}
const ENDPOINTS = {
  status:       { path: "/api/pulp/api/v3/status/",               needsAuth: false },
  repositories: { path: "/api/pulp/default/api/v3/repositories/", needsAuth: true  },
} satisfies Record<string, Endpoint>;

type EndpointName = keyof typeof ENDPOINTS;
type Profile = "load" | "stress";

// Pick one with the ENDPOINT env var (default: status).
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

// The ramp: hold each VU level so the metric settles, then ramp down. Higher VUs = more
// concurrent requests = higher `pulp_api_active_connections`.
//
// PROFILE picks the shape of the test (default "load"):
//   load   -- ramp to expected peak, hold: "do we meet SLOs at normal traffic?"
//   stress -- ramp PAST peak until it breaks: "where's the ceiling and how does it fail?"
//
// Each endpoint has its own ramp because their capacities differ hugely:
//   status       -- light (~0.5s), push hard to find the worker-saturation ceiling.
//   repositories -- heavy (~2s DB query on the SHARED stage RDS), so ramp gently and stop low.
type Stage = { target: number; duration: string };
// satisfies Record<Profile, Record<EndpointName, ...>> forces every profile to define a ramp
// for every endpoint -- add an endpoint above and this won't compile until you give it ramps.
const RAMPS = {
  load: {
    status: [
      { target: 12, duration: "2m" },
      { target: 24, duration: "2m" },
      { target: 48, duration: "2m" },
      { target: 96, duration: "2m" },
      { target: 0,  duration: "30s" }, // cool down
    ],
    repositories: [
      { target: 6,  duration: "2m" },
      { target: 12, duration: "2m" },
      { target: 24, duration: "2m" },
      { target: 0,  duration: "30s" }, // cool down
    ],
  },
  // Stress: keep climbing well past saturation until latency/errors break.
  stress: {
    status: [
      { target: 96,  duration: "90s" },
      { target: 200, duration: "90s" },
      { target: 400, duration: "90s" },
      { target: 600, duration: "90s" },
      { target: 0,   duration: "30s" }, // cool down
    ],
    repositories: [
      { target: 24, duration: "90s" },
      { target: 48, duration: "90s" },
      { target: 96, duration: "90s" },
      { target: 0,  duration: "30s" }, // cool down
    ],
  },
} satisfies Record<Profile, Record<EndpointName, Stage[]>>;

const profile = (__ENV.PROFILE || "load") as Profile;
const stages = RAMPS[profile]?.[endpointName];
if (!stages) {
  throw new Error(`No ramp for PROFILE "${profile}" / ENDPOINT "${endpointName}"`);
}

export const options: Options = {
  insecureSkipTLSVerify: true, // stage uses a self-signed cert
  stages,
};

// What each virtual user does, over and over: one GET, check it returned 200.
export default function () {
  const response = http.get(targetUrl, { headers, timeout: "60s" });
  check(response, { "status is 200": (r) => r.status === 200 });
}
