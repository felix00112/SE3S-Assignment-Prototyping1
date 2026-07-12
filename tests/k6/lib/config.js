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

function parseTimeUnit(value, fallback) {
  return value && value.trim() ? value.trim() : fallback;
}

function parseStages(value, fallback) {
  if (!value || !value.trim()) {
    return fallback;
  }

  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      return fallback;
    }

    return parsed;
  } catch (_) {
    return fallback;
  }
}

export const baseUrl = __ENV.BASE_URL || 'http://api:8000';
export const eventId = __ENV.EVENT_ID || '1';

export function buildConstantOptions() {
  return {
    vus: parsePositiveInt(__ENV.K6_VUS, 20),
    duration: parseDuration(__ENV.K6_DURATION, '1m'),
  };
}

// Open-loop scaling baseline. An arrival-rate executor MUST live inside a `scenarios`
// block — a bare top-level `executor` is silently ignored by k6 (it falls back to a
// single-VU closed loop). Its knobs use BASELINE_* env vars, NOT K6_VUS / K6_DURATION:
// those are reserved by k6 and, if set, override the whole `scenarios` block with a
// top-level closed-loop config.
//
// It RAMPS the offered load from BASELINE_START_RATE up to BASELINE_RATE over
// BASELINE_DURATION, independent of how fast the cluster responds. One run per cluster
// reveals that cluster's ceiling: accepted/s climbs then plateaus, and 503s / latency /
// dropped iterations start once the offered rate passes what it can handle. The
// plateau (the "knee") rises with node count — no manual rate sweep needed.
export function buildBaselineOptions() {
  return {
    scenarios: {
      baseline: {
        executor: 'ramping-arrival-rate',
        startRate: parsePositiveInt(__ENV.BASELINE_START_RATE, 100),
        timeUnit: '1s',
        preAllocatedVUs: parsePositiveInt(__ENV.BASELINE_PREALLOCATED_VUS, 200),
        maxVUs: parsePositiveInt(__ENV.BASELINE_MAX_VUS, 2000),
        stages: [
          {
            target: parsePositiveInt(__ENV.BASELINE_RATE, 4000),
            duration: parseDuration(__ENV.BASELINE_DURATION, '2m'),
          },
        ],
      },
    },
  };
}

// NOTE: stages are overridden via the STAGES env var, NOT K6_STAGES. K6_STAGES is a
// reserved k6 variable that k6 parses itself (in its own "10s:100,..." format) before
// the script runs, so passing JSON in K6_STAGES errors out. STAGES has no K6_ prefix,
// so k6 leaves it alone and we read it as JSON via __ENV.STAGES.
export function buildDynamicOptions() {
  return {
    stages: parseStages(__ENV.STAGES, [
      { duration: '1m', target: 100 },
      { duration: '2m', target: 1000 },
      { duration: '2m', target: 500 },
      { duration: '1m', target: 750 },
      { duration: '30s', target: 0 },
    ]),
  };
}

export function buildFlashSaleOptions() {
  // Flash-sale burst: a link opens and users pile in fast. 0 -> 50 -> 200,
  // hold at the peak, then drain. Modest peak on purpose (small VMs), and with
  // reused user ids the rate limiter sheds most of it anyway.
  return {
    stages: parseStages(__ENV.STAGES, [
      { duration: '20s', target: 50 },
      { duration: '40s', target: 200 },
      { duration: '30s', target: 200 },
      { duration: '20s', target: 0 },
    ]),
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
