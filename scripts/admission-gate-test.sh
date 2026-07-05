#!/usr/bin/env bash
# Behavioral test for the queue-capacity admission gate.
#
# Asserts:
#   1. a booking is admitted (200) when the queue has room
#   2. once the queue is filled to capacity, a booking is rejected with 503
#   3. the 503 response carries a Retry-After header
#   4. after the queue drains, bookings are admitted again
#
# The gate rejects at the enqueue step, so no worker is needed. The test fills
# the queue directly via redis-cli to reach capacity. MAX must match the API's
# ADMISSION_MAX_QUEUE_LENGTH (docker-compose default 100).
# Usage: scripts/admission-gate-test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="${API_URL:-http://localhost:8000}"
MAX="${ADMISSION_MAX_QUEUE_LENGTH:-100}"
EVENT_ID="${EVENT_ID:-1}"
QUEUE_KEY="event:${EVENT_ID}:booking_queue"

fail=0
report() { echo "$1  $2"; [ "$1" = "FAIL" ] && fail=1; }

redis() { docker compose exec -T redis redis-cli "$@"; }

post_code() { # post_code <user_id> -> prints HTTP status
    curl -s -o /dev/null -w "%{http_code}" -X POST "$API/events/${EVENT_ID}/book" \
        -H "Content-Type: application/json" -d "{\"user_id\": \"$1\"}"
}

# Clean slate (also clears the rate-limiter buckets so 200s are not thrown off).
scripts/reset.sh >/dev/null || { echo "FAIL  reset step failed" >&2; exit 1; }

USER="adm-$$-$(date +%s)"

# --- 1. admitted with room ---
code=$(post_code "$USER-a")
if [ "$code" = "200" ]; then
    report PASS "booking admitted (200) with room in queue"
else
    report FAIL "expected 200 with empty queue, got $code"
fi

# --- fill the queue to capacity directly ---
redis EVAL \
    "for i=1,tonumber(ARGV[1]) do redis.call('RPUSH', KEYS[1], 'filler') end return redis.call('LLEN', KEYS[1])" \
    1 "$QUEUE_KEY" "$MAX" >/dev/null
qlen=$(redis LLEN "$QUEUE_KEY")

# --- 2. rejected at capacity ---
code=$(post_code "$USER-b")
if [ "$code" = "503" ]; then
    report PASS "booking rejected (503) at capacity (queue length $qlen >= $MAX)"
else
    report FAIL "expected 503 at capacity, got $code"
fi

# --- 3. 503 carries Retry-After ---
retry_after=$(curl -s -D - -o /dev/null -X POST "$API/events/${EVENT_ID}/book" \
    -H "Content-Type: application/json" -d "{\"user_id\": \"$USER-c\"}" \
    | grep -i '^retry-after:' | tr -d '\r' | awk '{print $2}')
if [ -n "$retry_after" ]; then
    report PASS "503 carries Retry-After: $retry_after"
else
    report FAIL "503 missing Retry-After header"
fi

# --- 4. admitted again after drain ---
redis DEL "$QUEUE_KEY" >/dev/null
code=$(post_code "$USER-d")
if [ "$code" = "200" ]; then
    report PASS "booking admitted (200) again after queue drained"
else
    report FAIL "expected 200 after drain, got $code"
fi

exit "$fail"
