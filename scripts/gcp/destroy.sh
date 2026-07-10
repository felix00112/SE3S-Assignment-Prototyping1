#!/usr/bin/env bash
set -euo pipefail

# Destroy the GCP booking cluster (all VMs, network, firewall rules). Run this after
# recording results for a configuration — it stops all billing for that deployment.
#
# Usage:
#   scripts/gcp/destroy.sh -p PROJECT_ID
#
#   -p  GCP project id  (PROJECT)  [required]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT/infrastructure/terraform/gcp"

PROJECT="${PROJECT:-}"

usage() { sed -n '3,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while getopts "p:h" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "ERROR: project id required (-p PROJECT_ID or PROJECT=...)" >&2
  usage
  exit 1
fi

echo ">> Destroying all GCP resources for project $PROJECT"
terraform -chdir="$TF_DIR" destroy -auto-approve -var="project_id=$PROJECT"
echo ">> Destroyed."
