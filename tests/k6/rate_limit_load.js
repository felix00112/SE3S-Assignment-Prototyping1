import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';
import exec from 'k6/execution';
import { baseUrl, buildConstantOptions, eventId } from './lib/config.js';

export const options = buildConstantOptions();

const throttledRate = new Rate('throttled_requests');

export default function () {
  // every iteration of a VU reuses the same id
  // that user hammers the endpoint and trips the per-user rate limiter
  const userId = `rl-user-${exec.vu.idInTest}`;
  const url = `${baseUrl}/events/${eventId}/book`;

  const payload = JSON.stringify({
    user_id: userId,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const res = http.post(url, payload, params);

  const throttled = res.status === 429;
  throttledRate.add(throttled);

  // 200/201 = accepted, 429 = correctly throttled. 
  // Both are expected here; anything else is a real failure.
  check(res, {
    'accepted or throttled': (r) =>
      r.status === 200 || r.status === 201 || r.status === 429,
  });
}
