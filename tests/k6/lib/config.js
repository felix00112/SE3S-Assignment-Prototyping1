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
