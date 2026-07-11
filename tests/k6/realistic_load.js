import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';
import { baseUrl, buildConstantOptions, eventId } from './lib/config.js';
import { recordOutcome } from './lib/outcome.js';

// Realistic user load: each VU is ONE user (stable id) that makes a booking
// attempt, then "thinks" (pauses) before the next — like a real person, not a
// flat-out bot. The think time makes each VU spend most of its time idle, so it
// contributes almost nothing to concurrency: a VU here is ~100x lighter than a
// no-sleep VU in constant_load. That means:
//   - K6_VUS maps to "number of concurrent users" (not a stress multiplier),
//   - you can run thousands of VUs => thousands of distinct users, safely,
//   - a user pacing at ~1 req/s sits near the rate-limiter refill, so most
//     requests are accepted with occasional 429s — realistic behaviour.
//
// Knobs: K6_VUS (concurrent users), K6_DURATION, THINK_TIME (mean seconds
// between a user's requests, default 1s).
export const options = buildConstantOptions();

const thinkTime = Number.parseFloat(__ENV.THINK_TIME || '1');

export default function () {
  const userId = `user-${exec.vu.idInTest}`; // one user per VU
  const res = http.post(
    `${baseUrl}/events/${eventId}/book`,
    JSON.stringify({ user_id: userId }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  recordOutcome(res);
  check(res, {
    'accepted / throttled / shed': (r) =>
      r.status === 200 || r.status === 201 || r.status === 429 || r.status === 503,
  });

  // Think time with jitter (0.5x-1.5x of THINK_TIME) so users don't march in lockstep.
  sleep(thinkTime * (0.5 + Math.random()));
}
