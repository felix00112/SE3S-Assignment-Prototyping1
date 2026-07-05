#!/usr/bin/env bash
# Behavioral test for the per-user token-bucket rate limiter.
#
# Asserts, without hardcoding the configured capacity:
#   1. a rapid burst from one user eventually gets 429 (limiter engages)
#   2. the 429 response carries a Retry-After header
#   3. a different user is not throttled by the first user's burst (isolation)
#   4. the throttled user recovers after tokens refill
#
# Rate limiting happens in the API before enqueueing, so no worker or seat
# seeding is needed. Requires api + redis running (`docker compose up`) with the
# limiter enabled (RATE_LIMIT_ENABLED != false).
# Usage: scripts/rate-limit-test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="${API_URL:-http://localhost:8000}"
BURST="${BURST:-15}"          # must exceed RATE_LIMIT_CAPACITY
REFILL_WAIT="${REFILL_WAIT:-2}"  # seconds to wait for recovery

fail=0
report() { # report <PASS|FAIL> <message>
    echo "$1  $2"
    [ "$1" = "FAIL" ] && fail=1
}

post_code() { # post_code <user_id> -> prints HTTP status
    curl -s -o /dev/null -w "%{http_code}" -X POST "$API/events/1/book" \
        -H "Content-Type: application/json" -d "{\"user_id\": \"$1\"}"
}

# Fresh buckets: flush limiter state (reset.sh also reseeds seats, harmless here).
scripts/reset.sh >/dev/null || { echo "FAIL  reset step failed" >&2; exit 1; }

USER="rl-$$-$(date +%s)"

# --- 1. limiter engages, count leading 200s ---
allowed=0
saw_429=0
for _ in $(seq 1 "$BURST"); do
    code=$(post_code "$USER")
    if [ "$code" = "200" ]; then
        [ "$saw_429" -eq 0 ] && allowed=$((allowed + 1))
    elif [ "$code" = "429" ]; then
        saw_429=1
    else
        report FAIL "unexpected status $code during burst"
    fi
done
if [ "$saw_429" -eq 1 ] && [ "$allowed" -ge 1 ]; then
    report PASS "limiter engages (allowed $allowed, then 429) over burst of $BURST"
else
    report FAIL "limiter did not engage (allowed=$allowed, saw_429=$saw_429)"
fi

# --- 2. 429 carries Retry-After ---
retry_after=$(curl -s -D - -o /dev/null -X POST "$API/events/1/book" \
    -H "Content-Type: application/json" -d "{\"user_id\": \"$USER\"}" \
    | grep -i '^retry-after:' | tr -d '\r' | awk '{print $2}')
if [ -n "$retry_after" ]; then
    report PASS "429 carries Retry-After: $retry_after"
else
    report FAIL "429 missing Retry-After header"
fi

# --- 3. isolation: a different user is not throttled ---
other_code=$(post_code "other-$USER")
if [ "$other_code" = "200" ]; then
    report PASS "different user unaffected (200) while first is throttled"
else
    report FAIL "different user got $other_code, expected 200 (isolation broken)"
fi

# --- 4. recovery after refill ---
sleep "$REFILL_WAIT"
recovered=$(post_code "$USER")
if [ "$recovered" = "200" ]; then
    report PASS "throttled user recovers (200) after ${REFILL_WAIT}s refill"
else
    report FAIL "user still throttled ($recovered) after ${REFILL_WAIT}s"
fi

exit "$fail"
