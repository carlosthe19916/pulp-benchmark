// Stress test -- ramp PAST saturation, pushing until latency and errors break.
//
// Questions it helps answer:
//   - What's the maximum throughput before latency/errors blow up -- where is the ceiling?
//   - HOW does it degrade past that point: graceful queueing, or timeouts and 5xx?
//   - Does status hit the expected worker-saturation ceiling (5 gunicorn workers per pod)?
//   - Can the autoscaler scale fast enough to keep up with a surge, or does it fall behind?
//   - What breaks first -- the pods, the gunicorn workers, or the shared DB?
//
// For behavior within the expected envelope (SLOs, calibration), see load-test.ts.

import { Options } from "k6/options";
import { EndpointName, Stage, stagesFor } from "./common.ts";

export { request as default } from "./common.ts";

// Keep climbing well past saturation, holding each level briefly (90s) to push through it, then
// cool down. Each endpoint has its own ramp because their capacities differ hugely:
//   status       -- light (~0.5s); push hard to find the worker-saturation ceiling.
//   repositories -- heavy (~2s DB query on the SHARED stage RDS), so climb gently and stop lower.
// The `satisfies` forces a ramp for every endpoint -- add one to ENDPOINTS and this won't compile
// until you give it a ramp here too.
const RAMPS = {
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
} satisfies Record<EndpointName, Stage[]>;

export const options: Options = {
  insecureSkipTLSVerify: true, // stage uses a self-signed cert
  stages: stagesFor(RAMPS),
};
