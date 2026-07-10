import { check } from 'k6';
import { Counter } from 'k6/metrics';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { baseUrl, eventId } from './lib/config.js';
import { bookOnce, reservationIdFrom, pollReservation } from './lib/booking.js';

// Correctness test for the atomic reserve (reserve_atomic.lua): fire far more
// bookings than there are seats and prove the system never sells more seats than
// exist. Unlike the throughput scripts, this one deliberately runs against a
// SMALL seat count so seats actually run out.
//
// Seed Redis with EXPECTED_SEATS seats before running, e.g. locally:
//   redis-cli SET event:1:seats_available 100 && redis-cli DEL event:1:reserved_users
// or on GCP deploy with -var="initial_seats=100".

const expectedSeats = Number.parseInt(__ENV.EXPECTED_SEATS || '100', 10);
const totalRequests = Number.parseInt(
  __ENV.TOTAL_REQUESTS || String(expectedSeats * 3),
  10,
);
// NOTE: not K6_VUS — that is a reserved k6 env var that would override the
// scenarios config below (forcing iterations = vus). Use our own name.
const vus = Number.parseInt(__ENV.OVERSELL_VUS || '20', 10);

export const options = {
  scenarios: {
    oversell: {
      executor: 'shared-iterations',
      vus,
      iterations: totalRequests,
      maxDuration: __ENV.K6_MAX_DURATION || '3m',
    },
  },
  thresholds: {
    // The core invariant: never more reservations than seats.
    reserved: [`count<=${expectedSeats}`],
    // Fresh user per request, so a duplicate would be a real bug.
    duplicate: ['count==0'],
    // Any status that isn't reserved/sold_out/duplicate is unexpected.
    unexpected_status: ['count==0'],
  },
};

const reserved = new Counter('reserved');
const soldOut = new Counter('sold_out');
const duplicate = new Counter('duplicate');
const rejected = new Counter('rejected'); // 429 / 503 before enqueue
const unexpectedStatus = new Counter('unexpected_status');

export default function () {
  const userId = uuidv4(); // distinct user per request, all competing for seats
  const res = bookOnce(baseUrl, eventId, userId);

  // Rate-limited or admission-gated before ever reaching the queue.
  if (res.status === 429 || res.status === 503) {
    rejected.add(1);
    return;
  }

  check(res, { 'booking accepted (200/201)': (r) => r.status === 200 || r.status === 201 });

  const reservationId = reservationIdFrom(res);
  if (!reservationId) {
    unexpectedStatus.add(1);
    return;
  }

  const finalStatus = pollReservation(baseUrl, reservationId, {
    intervalSeconds: Number.parseFloat(__ENV.POLL_INTERVAL || '0.1'),
  });

  switch (finalStatus) {
    case 'reserved':
      reserved.add(1);
      break;
    case 'sold_out':
      soldOut.add(1);
      break;
    case 'duplicate':
      duplicate.add(1);
      break;
    default:
      // includes "pending" (never resolved) and anything unexpected
      unexpectedStatus.add(1);
  }
}
