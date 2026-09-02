// Load test -- ramp TO the expected peak and hold each level so the metric settles.
//
// Questions it helps answer:
//   - Do we meet our SLOs (latency percentiles, error rate) at normal peak traffic?
//   - At that traffic, what's the steady-state avg/pod, and does the autoscaler add pods at the
//     right point (above 4/pod)?
//   - Does Little's Law hold -- avg/pod ~= requests_in_flight / pods? (status tops out near 5/pod,
//     the 5 gunicorn workers per pod.)
//   - Is the autoscaler calibrated correctly for the traffic we actually expect?
//
// To find the breaking point instead, see stress-test.ts.

import { Options } from "k6/options";
import { EndpointName, Stage, stagesFor } from "./common.ts";

export { request as default } from "./common.ts";

// Ramp to expected peak, holding each level (2m) long enough for the metric to settle, then cool
// down. Each endpoint has its own ramp because their capacities differ hugely:
//   status       -- light (~0.5s); we can hold real concurrency without stressing anything.
//   repositories -- heavy (~2s DB query on the SHARED stage RDS), so ramp gently and stop low.
// The `satisfies` forces a ramp for every endpoint -- add one to ENDPOINTS and this won't compile
// until you give it a ramp here too.
const RAMPS = {
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
} satisfies Record<EndpointName, Stage[]>;

export const options: Options = {
  insecureSkipTLSVerify: true, // stage uses a self-signed cert
  stages: stagesFor(RAMPS),
};
