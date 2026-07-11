#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT/infrastructure/terraform/gcp}"

SCENARIO="${1:-constant_load.js}"
if [[ "$SCENARIO" != *.js ]]; then
  SCENARIO="${SCENARIO}.js"
fi

if [ ! -d "$TF_DIR" ]; then
  echo "Terraform directory not found: $TF_DIR" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required" >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is required" >&2
  exit 1
fi

api_url="$(terraform -chdir="$TF_DIR" output -raw api_url)"
loadgen_name="$(terraform -chdir="$TF_DIR" output -raw load_generator_instance_name 2>/dev/null || true)"
ssh_command="$(terraform -chdir="$TF_DIR" output -raw load_generator_ssh_command 2>/dev/null || true)"

if [ -z "$loadgen_name" ] || [ "$loadgen_name" = "null" ] || [ -z "$ssh_command" ] || [ "$ssh_command" = "null" ]; then
  echo "No load-generator VM is available. Re-apply Terraform with -var='load_generator_enabled=true'." >&2
  exit 1
fi

read -r -a ssh_parts <<<"$ssh_command"

env_assignments=("BASE_URL='$api_url'" "EVENT_ID='${EVENT_ID:-1}'")

if [ -n "${K6_VUS:-}" ]; then
  env_assignments+=("K6_VUS='${K6_VUS}'")
fi

if [ -n "${K6_DURATION:-}" ]; then
  env_assignments+=("K6_DURATION='${K6_DURATION}'")
fi

if [ -n "${STAGES:-}" ]; then
  env_assignments+=("STAGES='${STAGES}'")
fi

remote_command="sudo $(printf "%s " "${env_assignments[@]}")/usr/local/bin/run-k6.sh '$SCENARIO'"

echo "Running $SCENARIO from $loadgen_name against $api_url"
"${ssh_parts[@]}" --command "$remote_command"
