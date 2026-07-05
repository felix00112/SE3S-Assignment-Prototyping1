#!/usr/bin/env bash
# Reset Redis to a clean, seeded state for the single-event MVP.
# Usage: scripts/reset.sh [SEATS]   (default 3)
#
# Flushes ALL Redis state, then seeds event 1 with SEATS available seats.
# Stop any running worker before calling this so leftover queue items are not
# drained against the freshly seeded seat count.
set -euo pipefail

SEATS="${1:-3}"
EVENT_ID="${EVENT_ID:-1}"

redis() { docker compose exec -T redis redis-cli "$@"; }

redis FLUSHALL >/dev/null
redis SET "event:${EVENT_ID}:seats_available" "$SEATS" >/dev/null
redis DEL "event:${EVENT_ID}:reserved_users" >/dev/null

echo "Reset done: event:${EVENT_ID}:seats_available=$(redis GET "event:${EVENT_ID}:seats_available")"
