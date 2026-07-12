function parsePositiveInt(value, fallback) {
  if (!value) {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function parseDuration(value, fallback) {
  return value && value.trim() ? value.trim() : fallback;
}

export const baseUrl = __ENV.BASE_URL || 'http://api:8000';
export const eventId = __ENV.EVENT_ID || '1';

export function buildConstantOptions() {
  return {
    vus: parsePositiveInt(__ENV.K6_VUS, 20),
    duration: parseDuration(__ENV.K6_DURATION, '1m'),
  };
}

// Trips BOTH protection layers in a single run using two concurrent populations,
// one per gate, so they don't fight each other (the rate limiter runs first in the
// request path, so anything it throttles never reaches the admission gate):
//   - `bots`:  a small pool of STABLE user ids hammering closed-loop as the same
//              users -> each blows past its token bucket -> 429 (rate limiter).
//   - `flood`: a legit crowd with a UNIQUE uuid per request, offered OPEN-LOOP at a
//              fixed arrival rate -> fresh users sail past the rate limiter and pile
//              onto the booking queue faster than the single worker drains -> 503
//              (admission gate).
// Every sample carries a `role` tag (bots/flood) plus k6's built-in `scenario` tag,
// so the 429s and 503s are cleanly attributable to each population.
//
// This is a CORRECTNESS demonstration of the two gates, NOT an API stress test. The
// defaults are sized to show both gates rejecting cleanly, staying comfortably within
// the API's serving capacity so requests get real 429/503 responses instead of dropped
// connections (EOF). The admission gate trips easily because the worker drains only
// ~100/s (WORKER_BATCH_SIZE=100 / WORKER_INTERVAL_SECONDS=1.0), so FLOOD_RATE only needs
// to sit modestly above that to back the queue up — not saturate the front door.
//
// Knobs use COMBINED_*/BOTS_*/FLOOD_* (NOT K6_VUS/K6_DURATION, which are reserved and
// would replace the whole scenarios block with a single closed loop). Keep the worker
// RUNNING, or the queue never drains and everything trivially becomes 503. If you see
// EOF / "server closed idle connection", FLOOD_RATE is above what the API can serve —
// LOWER it (that's front-door saturation, not the admission gate).
export function buildCombinedGatesOptions() {
  const duration = parseDuration(__ENV.COMBINED_DURATION, '1m');
  return {
    scenarios: {
      bots: {
        executor: 'constant-vus',
        exec: 'bots',
        vus: parsePositiveInt(__ENV.BOTS_VUS, 20),
        duration,
        tags: { role: 'bots' },
      },
      flood: {
        executor: 'constant-arrival-rate',
        exec: 'flood',
        // ~2.5x the ~100/s worker drain: enough to fill the queue and trip the
        // admission gate within seconds, while staying well under the single-worker
        // API's serving capacity so there are no dropped connections.
        rate: parsePositiveInt(__ENV.FLOOD_RATE, 250),
        timeUnit: '1s',
        duration,
        preAllocatedVUs: parsePositiveInt(__ENV.FLOOD_PREALLOCATED_VUS, 50),
        maxVUs: parsePositiveInt(__ENV.FLOOD_MAX_VUS, 300),
        tags: { role: 'flood' },
      },
    },
  };
}
