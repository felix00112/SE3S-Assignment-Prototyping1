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

export function buildDynamicOptions() {
  return {
    stages: parseStages(__ENV.K6_STAGES, [
      { duration: '1m', target: 100 },
      { duration: '2m', target: 1000 },
      { duration: '2m', target: 500 },
      { duration: '1m', target: 750 },
      { duration: '30s', target: 0 },
    ]),
  };
}
