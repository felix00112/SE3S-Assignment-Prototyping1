import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { baseUrl, buildConstantOptions, eventId } from './lib/config.js';
import { bookOnce, reservationIdFrom, pollReservation } from './lib/booking.js';

// End-to-end latency test: measures how long a booking takes to go from POST
// (status "pending") to a resolved outcome (reserved/sold_out) as seen by the
// client polling GET /reservations/{id}. This is the only scenario that exercises
// the async part of the design and the status endpoint; the throughput scripts
// only look at the immediate POST response.
//
// Uses the same K6_VUS / K6_DURATION knobs as constant_load.js. Seed plenty of
// seats (e.g. initial_seats=100000) so latency isn't cut short by sold_out.
//
// Note: resolution is bounded by POLL_INTERVAL (default 100ms) — the measured
// time is "time until the client next observed a resolved status", not the
// worker's internal processing time.

export const options = buildConstantOptions();

const e2eResolveMs = new Trend('e2e_resolve_ms', true);
const resolved = new Counter('resolved');
const rejected = new Counter('rejected'); // 429 / 503 before enqueue
const unresolved = new Counter('unresolved'); // still pending when we gave up

export default function () {
  const userId = uuidv4();

  const start = Date.now();
  const res = bookOnce(baseUrl, eventId, userId);

  if (res.status === 429 || res.status === 503) {
    rejected.add(1);
    return;
  }

  check(res, { 'booking accepted (200/201)': (r) => r.status === 200 || r.status === 201 });

  const reservationId = reservationIdFrom(res);
  if (!reservationId) {
    unresolved.add(1);
    return;
  }

  const finalStatus = pollReservation(baseUrl, reservationId, {
    intervalSeconds: Number.parseFloat(__ENV.POLL_INTERVAL || '0.1'),
  });

  if (finalStatus === 'pending') {
    unresolved.add(1);
    return;
  }

  e2eResolveMs.add(Date.now() - start);
  resolved.add(1);
}
