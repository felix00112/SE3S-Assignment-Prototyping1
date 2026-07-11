#!/usr/bin/env bash
set -euo pipefail

# Run a k6 scenario from the load-generator VM against the load balancer, fetch the
# reports (CSV time series + summary JSON) back to a local folder, and print the
# headline numbers.
#
# Usage:
#   scripts/gcp/run-tests.sh -p PROJECT_ID [-z ZONE] [-o OUTDIR] [SCENARIO]
#
#   SCENARIO   k6 script name (default constant_load). ".js" optional.
#              e.g. constant_load | dynamic_load | rate_limit_load
#   -p  GCP project id   (PROJECT)  [required]
#   -z  GCP zone         (ZONE)     [default europe-west3-a]
#   -o  local out dir    (OUTDIR)   [default results/<timestamp>-<scenario>]
#
# Load shape overrides are passed through as env vars, e.g.:
#   K6_VUS=100 K6_DURATION=2m scripts/gcp/run-tests.sh -p PROJECT constant_load
#   K6_STAGES='[...]'          scripts/gcp/run-tests.sh -p PROJECT dynamic_load

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT/infrastructure/terraform/gcp"

PROJECT="${PROJECT:-}"
ZONE="${ZONE:-europe-west3-a}"
OUTDIR="${OUTDIR:-}"

usage() { sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while getopts "p:z:o:h" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    z) ZONE="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

SCENARIO="${1:-constant_load}"
[[ "$SCENARIO" == *.js ]] || SCENARIO="${SCENARIO}.js"

if [ -z "$PROJECT" ]; then
  echo "ERROR: project id required (-p PROJECT_ID or PROJECT=...)" >&2
  usage
  exit 1
fi

api_url="$(terraform -chdir="$TF_DIR" output -raw api_url)"
loadgen_name="$(terraform -chdir="$TF_DIR" output -raw load_generator_instance_name 2>/dev/null || true)"

if [ -z "$loadgen_name" ] || [ "$loadgen_name" = "null" ]; then
  echo "ERROR: no load-generator VM. Redeploy with -g true (load_generator_enabled=true)." >&2
  exit 1
fi

OUTDIR="${OUTDIR:-$ROOT/results/$(date +%Y%m%d-%H%M%S)-${SCENARIO%.js}}"
mkdir -p "$OUTDIR"

# Wait until the load balancer actually serves before starting k6. Without this,
# a test launched too soon after deploy records a burst of "connection refused"
# (status 0) while Nginx is still booting, which poisons the throughput/latency.
READY_TIMEOUT="${READY_TIMEOUT:-240}"
echo ">> Waiting for $api_url to be ready (up to ${READY_TIMEOUT}s)..."
ready=0
for _ in $(seq 1 $((READY_TIMEOUT / 2))); do
  if curl -sf --max-time 3 "$api_url/health" >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "ERROR: $api_url did not become ready within ${READY_TIMEOUT}s." >&2
  echo "       Check the coordinator startup: gcloud compute ssh se3s-mvp-vm ..." >&2
  exit 1
fi
echo ">> Load balancer is ready."

# Forward BASE_URL (the LB) + any K6_* load-shape overrides to the remote helper.
env_assignments=("BASE_URL='$api_url'" "EVENT_ID='${EVENT_ID:-1}'")
for v in K6_VUS K6_DURATION K6_STAGES; do
  if [ -n "${!v:-}" ]; then env_assignments+=("$v='${!v}'"); fi
done
remote_command="sudo $(printf "%s " "${env_assignments[@]}")/usr/local/bin/run-k6.sh '$SCENARIO'"

echo ">> Running $SCENARIO from $loadgen_name against $api_url"
gcloud compute ssh "$loadgen_name" --zone "$ZONE" --project "$PROJECT" --command "$remote_command"

echo ">> Fetching reports into $OUTDIR"
gcloud compute scp --recurse "$loadgen_name:/opt/se3s/k6-out" "$OUTDIR" --zone "$ZONE" --project "$PROJECT"

# Print headline numbers from the newest summary json (best-effort). Sort by the
# timestamp embedded in the filename, not mtime (scp gives all files the same mtime).
latest_summary="$(ls "$OUTDIR"/k6-out/summary-*.json 2>/dev/null | sort | tail -1 || true)"
if [ -n "$latest_summary" ] && command -v python3 >/dev/null 2>&1; then
  echo ">> Headline metrics ($latest_summary):"
  python3 "$ROOT/scripts/gcp/summarize.py" "$latest_summary" || true
fi

echo ">> Done. Raw CSV (time series) + summary JSON are under: $OUTDIR/k6-out/"
