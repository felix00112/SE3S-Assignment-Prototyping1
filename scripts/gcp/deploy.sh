#!/usr/bin/env bash
set -euo pipefail

# Deploy the GCP booking cluster: 1 / 3 / 5 API nodes (same instance type) with the
# coordinator hosting Redis + worker + Nginx LB, plus an optional k6 load generator.
#
# Usage:
#   scripts/gcp/deploy.sh -p PROJECT_ID [-n 1|3|5] [-m MACHINE] [-s SEATS] [-r REF] [-g true|false]
#
# Flags (env-var equivalents in parentheses):
#   -p  GCP project id           (PROJECT)     [required]
#   -n  node_count = API nodes   (NODES)       [default 1]
#   -m  machine_type             (MACHINE)     [default e2-medium]  (raise for vertical scaling)
#   -s  initial_seats            (SEATS)       [default 1000000]
#   -r  source_ref (pushed!)     (SOURCE_REF)  [default current git branch]
#   -g  load generator on/off    (LOADGEN)     [default true]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT/infrastructure/terraform/gcp"

PROJECT="${PROJECT:-}"
NODES="${NODES:-1}"
MACHINE="${MACHINE:-e2-medium}"
SEATS="${SEATS:-1000000}"
SOURCE_REF="${SOURCE_REF:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
LOADGEN="${LOADGEN:-true}"

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while getopts "p:n:m:s:r:g:h" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    n) NODES="$OPTARG" ;;
    m) MACHINE="$OPTARG" ;;
    s) SEATS="$OPTARG" ;;
    r) SOURCE_REF="$OPTARG" ;;
    g) LOADGEN="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "ERROR: project id required (-p PROJECT_ID or PROJECT=...)" >&2
  usage
  exit 1
fi

echo ">> Deploying node_count=$NODES machine_type=$MACHINE seats=$SEATS ref=$SOURCE_REF loadgen=$LOADGEN"

terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" apply -auto-approve \
  -var="project_id=$PROJECT" \
  -var="source_ref=$SOURCE_REF" \
  -var="node_count=$NODES" \
  -var="machine_type=$MACHINE" \
  -var="initial_seats=$SEATS" \
  -var="load_generator_enabled=$LOADGEN" \
  -var="worker_batch_size=100" \
  -var="worker_interval_seconds=1" \
  -var="worker_synthetic_dummy_mode=true"

echo
echo ">> Cluster is up. Give the VMs ~2-3 min to finish booting, then load-test via:"
echo "   Entry point (LB): $(terraform -chdir="$TF_DIR" output -raw api_url)"
echo "   scripts/gcp/run-tests.sh -p $PROJECT constant_load"
