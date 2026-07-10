import http from 'k6/http';
import { sleep } from 'k6';

// Shared helpers for scenarios that need to follow a booking through the async
// pipeline (POST /book -> worker -> reserve_atomic.lua -> GET /reservations/{id}).

const jsonHeaders = { headers: { 'Content-Type': 'application/json' } };

// Fire a single booking. Returns the raw k6 response so the caller can inspect
// the HTTP status (200/201 accepted, 429 rate-limited, 503 admission-gated).
export function bookOnce(baseUrl, eventId, userId) {
  return http.post(
    `${baseUrl}/events/${eventId}/book`,
    JSON.stringify({ user_id: userId }),
    jsonHeaders,
  );
}

// Pull the reservation_id out of a booking response body, or null if absent.
export function reservationIdFrom(res) {
  try {
    return res.json('reservation_id') || null;
  } catch (_) {
    return null;
  }
}

// Poll GET /reservations/{id} until the status is no longer "pending" (i.e. the
// worker has run the atomic reserve) or attempts run out. Returns the final
// status string, or "pending" if it never resolved within the budget.
export function pollReservation(baseUrl, reservationId, opts = {}) {
  const maxAttempts = opts.maxAttempts || 100;
  const intervalSeconds = opts.intervalSeconds || 0.1;

  for (let i = 0; i < maxAttempts; i++) {
    const res = http.get(`${baseUrl}/reservations/${reservationId}`);
    let status = null;
    try {
      status = res.json('status');
    } catch (_) {
      status = null;
    }

    if (status && status !== 'pending') {
      return status;
    }

    sleep(intervalSeconds);
  }

  return 'pending';
}
