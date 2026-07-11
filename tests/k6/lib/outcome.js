import { Counter } from 'k6/metrics';

// Domain-specific outcome counters. Everything else you need for plots — throughput
// (http_reqs), latency (http_req_duration), concurrent users (vus), total requests
// (iterations) — is already tracked natively by k6, so it is NOT re-implemented here.
// These counters only capture what k6 can't infer on its own: how many bookings were
// accepted vs. shed by each protection layer. They show up in both the CSV time series
// (--out csv) and the end-of-run summary (--summary-export).
const accepted = new Counter('accepted'); // 200 / 201 — enqueued
const rejectedRateLimited = new Counter('rejected_rate_limited'); // 429 — rate limiter
const rejectedAdmission = new Counter('rejected_admission'); // 503 — admission gate
const otherStatus = new Counter('other_status'); // anything unexpected

export function recordOutcome(res) {
  if (res.status === 200 || res.status === 201) {
    accepted.add(1);
  } else if (res.status === 429) {
    rejectedRateLimited.add(1);
  } else if (res.status === 503) {
    rejectedAdmission.add(1);
  } else {
    otherStatus.add(1);
  }
}
