import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';
import exec from 'k6/execution';
import { baseUrl, buildFlashSaleOptions, eventId } from './lib/config.js';
import { recordOutcome } from './lib/outcome.js';

// Flash-sale scenario: simulates a link going live and users rushing in
// (0 -> 50 -> 200 VUs, hold, drain). Unlike dynamic_load, it assigns a STABLE
// per-VU user id, so each simulated user hammers the endpoint as the same user
// and actually trips the per-user rate limiter (429). This is the realistic
// "everyone smashing buy on the same few accounts" shape.
//
// Override the ramp with K6_STAGES if needed.
export const options = buildFlashSaleOptions();

// Share of requests the rate limiter threw back (429) — the signal this test exists
// to produce, on top of the accepted/rejected counters from lib/outcome.js.
const throttledRate = new Rate('throttled_requests');

export default function () {
  // Stable per-VU id: peak 200 VUs => up to 200 distinct users, each making many
  // rapid requests (not a fresh user per request), so the rate limiter engages.
  const userId = `flash-user-${exec.vu.idInTest}`;
  const url = `${baseUrl}/events/${eventId}/book`;

  const payload = JSON.stringify({ user_id: userId });
  const params = { headers: { 'Content-Type': 'application/json' } };

  const res = http.post(url, payload, params);

  recordOutcome(res);
  throttledRate.add(res.status === 429);

  // 200/201 booked, 429 correctly throttled, 503 correctly admission-shed — all
  // expected under a flash-sale burst; anything else is a real failure.
  check(res, {
    'accepted / throttled / shed': (r) =>
      r.status === 200 || r.status === 201 || r.status === 429 || r.status === 503,
  });
}
