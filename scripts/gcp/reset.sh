#!/usr/bin/env bash
set -euo pipefail

# Reset the coordinator's Redis between tests on a live deployment: FLUSHALL, then
# reseed the seat counter. Use this when running MORE THAN ONE test against the same
# cluster (a fresh `deploy.sh` already starts with clean Redis, so you don't need it
# there). Clearing everything also resets rate-limiter token buckets, reserved_users,
# leftover queue items, reservation:* keys, and the constant-work dummy_* keys — so
# each run starts from an identical state.
#
# Usage:
#   scripts/gcp/reset.sh -p PROJECT_ID [-z ZONE] [-s SEATS] [-e EVENT_ID]
#
#   -p  GCP project id   (PROJECT)   [required]
#   -z  GCP zone         (ZONE)      [default europe-west3-a]
#   -s  seats to reseed  (SEATS)     [default 1000000]
#   -e  event id         (EVENT_ID)  [default 1]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT/infrastructure/terraform/gcp"

PROJECT="${PROJECT:-}"
ZONE="${ZONE:-europe-west3-a}"
SEATS="${SEATS:-1000000}"
EVENT_ID="${EVENT_ID:-1}"

usage() { sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while getopts "p:z:s:e:h" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    z) ZONE="$OPTARG" ;;
    s) SEATS="$OPTARG" ;;
    e) EVENT_ID="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "ERROR: project id required (-p PROJECT_ID or PROJECT=...)" >&2
  usage
  exit 1
fi

COORD="$(terraform -chdir="$TF_DIR" output -raw coordinator_instance_name)"

# FLUSHALL wipes the seat counter too, so reseed it in the same step.
remote="cd /opt/se3s/app \
  && sudo docker-compose -f docker-compose.gcp.yml exec -T redis redis-cli FLUSHALL \
  && sudo docker-compose -f docker-compose.gcp.yml exec -T redis redis-cli SET event:${EVENT_ID}:seats_available ${SEATS}"

echo ">> Resetting Redis on ${COORD} (FLUSHALL + seats=${SEATS})"
gcloud compute ssh "$COORD" --zone "$ZONE" --project "$PROJECT" --command "$remote"
echo ">> Redis reset."
