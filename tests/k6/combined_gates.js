import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { baseUrl, buildCombinedGatesOptions, eventId } from './lib/config.js';
import { recordOutcome } from './lib/outcome.js';

// One run, two concurrent populations, each aimed at a different protection layer.
// The gates are antagonistic (the rate limiter runs first, so whatever it throttles
// never reaches the admission gate), so instead of one crowd we split the load:
//
//   bots  - a SMALL pool of STABLE user ids hammering closed-loop as the same users.
//           Each blows past its per-user token bucket -> 429 (rate limiter). Their
//           admitted share is tiny, so they barely touch the queue.
//   flood - a legit flash-sale crowd, UNIQUE uuid per request, offered OPEN-LOOP at a
//           fixed arrival rate independent of response time. Fresh users sail past the
//           rate limiter and pile onto the booking queue faster than the single worker
//           drains -> 503 (admission gate).
//
// Both gates fire independently. Every metric sample carries a `role` tag (bots/flood)
// plus k6's built-in `scenario` tag, so 429s and 503s attribute cleanly to each group
// (e.g. filter `rejected_rate_limited{role:bots}` and `rejected_admission{role:flood}`
// in the CSV / summary). Knobs live in lib/config.js (COMBINED_*/BOTS_*/FLOOD_*).
export const options = buildCombinedGatesOptions();

// 429 (rate-limited) and 503 (admission-shed) are the expected outcomes of this test,
// not transport failures.
http.setResponseCallback(http.expectedStatuses(200, 201, 429, 503));

const jsonHeaders = { headers: { 'Content-Type': 'application/json' } };

function book(userId) {
  return http.post(
    `${baseUrl}/events/${eventId}/book`,
    JSON.stringify({ user_id: userId }),
    jsonHeaders,
  );
}

// A bot request may be throttled (429) or, if it slips through, still admission-shed
// (503) once the flood has filled the queue; both are fine here. Anything else (5xx,
// timeouts) is a real failure. Per-gate attribution comes from the role-tagged
// counters in lib/outcome.js, not from this check.
function expected(res) {
  return (
    res.status === 200 ||
    res.status === 201 ||
    res.status === 429 ||
    res.status === 503
  );
}

// Stable id per VU -> reuses the same user every iteration -> trips the rate limiter.
export function bots() {
  const res = book(`bot-user-${exec.vu.idInTest}`);
  recordOutcome(res);
  check(res, { 'bot request accepted / throttled / shed': expected });
}

// Fresh user per request -> passes the rate limiter -> floods the queue -> admission gate.
export function flood() {
  const res = book(uuidv4());
  recordOutcome(res);
  check(res, { 'flood request accepted / shed': expected });
}
