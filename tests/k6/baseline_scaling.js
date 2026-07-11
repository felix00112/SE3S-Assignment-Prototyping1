import http from 'k6/http';
import { check } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { baseUrl, buildBaselineOptions, eventId } from './lib/config.js';
import { recordOutcome } from './lib/outcome.js';

// Baseline for the 1 / 3 / 5 node comparison:
// - fresh user id per request, so rate limiting does not dominate the result
// - constant arrival rate, so each cluster sees the same offered load
// - 503 is treated as expected overload shedding, not as an HTTP transport failure
export const options = buildBaselineOptions();

http.setResponseCallback(http.expectedStatuses(200, 201, 503));

export default function () {
  const url = `${baseUrl}/events/${eventId}/book`;
  const payload = JSON.stringify({
    user_id: uuidv4(),
  });
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const res = http.post(url, payload, params);

  recordOutcome(res);
  check(res, {
    'accepted or admission-shed': (r) =>
      r.status === 200 || r.status === 201 || r.status === 503,
  });
}
