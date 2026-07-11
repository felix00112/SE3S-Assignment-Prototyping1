import http from 'k6/http';
import { check } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { baseUrl, buildBaselineOptions, eventId } from './lib/config.js';
import { recordOutcome } from './lib/outcome.js';

// Open-loop baseline for the 1 / 3 / 5 node scaling comparison.
//
// Uses a ramping-arrival-rate executor: it RAMPS the offered load from
// BASELINE_START_RATE up to BASELINE_RATE over BASELINE_DURATION, independent of how
// fast the cluster responds (no coordinated omission; every cluster sees the same
// offered curve). Fresh user id per request => the rate limiter does not dominate.
// 503 is expected admission shedding, marked so it does not count as a transport
// failure.
//
// ONE run per cluster size — no rate sweep. Each run reveals that cluster's ceiling:
// accepted/s climbs then plateaus (the "knee"), and 503s / latency / dropped
// iterations start once the offered rate passes what it can handle. The plateau rises
// with node count. Read it from the raw CSV (accepted/s over time) or watch where
// "dropped iterations" begin in the live output.
//   scripts/gcp/run-tests.sh -p PROJECT baseline_scaling
//   BASELINE_RATE=6000 BASELINE_DURATION=3m scripts/gcp/run-tests.sh -p PROJECT baseline_scaling
export const options = buildBaselineOptions();

http.setResponseCallback(http.expectedStatuses(200, 201, 503));

export default function () {
  const res = http.post(
    `${baseUrl}/events/${eventId}/book`,
    JSON.stringify({ user_id: uuidv4() }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  recordOutcome(res);
  check(res, {
    'accepted or admission-shed': (r) =>
      r.status === 200 || r.status === 201 || r.status === 503,
  });
}
