#!/usr/bin/env bash
# End-to-end smoke test for the booking MVP.
# Resets Redis to 3 seats, starts a worker, runs the five canonical booking
# scenarios, and asserts each reservation reaches the expected status.
#
# Requires: api + redis already running (`make up` / `docker compose up`),
# and a .venv containing the `redis` package.
# Usage: scripts/smoke-test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

API="${API_URL:-http://localhost:8000}"
PY="${PYTHON:-.venv/bin/python}"

# user_id -> expected final status
SCENARIO=(user-1 user-2 user-3 user-4 user-1)
EXPECT=(reserved reserved reserved sold_out duplicate)

echo "== reset to 3 seats =="
if ! scripts/reset.sh 3; then
    echo "FAIL  reset step failed; aborting so results are not run against stale state" >&2
    exit 1
fi

echo "== start worker =="
"$PY" -m workers.cells.worker >/tmp/smoke-worker.log 2>&1 &
WORKER_PID=$!
trap 'kill "$WORKER_PID" 2>/dev/null' EXIT
sleep 1

get_json() { "$PY" -c "import sys,json;print(json.load(sys.stdin)['$1'])"; }

fail=0
for i in "${!SCENARIO[@]}"; do
    user="${SCENARIO[$i]}"
    want="${EXPECT[$i]}"

    rid=$(curl -s -X POST "$API/events/1/book" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": \"$user\"}" | get_json reservation_id)

    # poll until the worker moves the status off "pending"
    status="pending"
    for _ in $(seq 1 20); do
        status=$(curl -s "$API/reservations/$rid" | get_json status)
        [ "$status" != "pending" ] && break
        sleep 0.25
    done

    if [ "$status" = "$want" ]; then
        echo "PASS  $user -> $status"
    else
        echo "FAIL  $user -> got '$status', expected '$want'"
        fail=1
    fi
done

exit "$fail"
