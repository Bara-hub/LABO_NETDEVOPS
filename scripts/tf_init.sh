#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 cml" >&2
  exit 2
fi
TARGET="$1"
DIR="terraform/${TARGET}"
if [[ ! -d "$DIR" ]]; then
  echo "Répertoire Terraform introuvable : ${DIR}" >&2
  exit 2
fi

BACKEND_FILE="${DIR}/backend.gitlab.tf"
if [[ -n "${CI_API_V4_URL:-}" && -n "${CI_PROJECT_ID:-}" && -n "${CI_JOB_TOKEN:-}" ]]; then
  # Fichier éphémère non versionné : permet d'utiliser le backend HTTP dans GitLab CI,
  # sans imposer ce backend aux exécutions locales.
  cat > "$BACKEND_FILE" <<'EOF'
terraform {
  backend "http" {}
}
EOF
  ADDR="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${TARGET}"
  terraform -chdir="$DIR" init -input=false -reconfigure \
    -backend-config="address=${ADDR}" \
    -backend-config="lock_address=${ADDR}/lock" \
    -backend-config="unlock_address=${ADDR}/lock" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5" \
    -backend-config="username=gitlab-ci-token" \
    -backend-config="password=${CI_JOB_TOKEN}"
else
  # Le cache .terraform peut conserver un backend HTTP d'une exécution précédente.
  # -reconfigure choisit le backend local sans migrer automatiquement un état distant.
  rm -f "$BACKEND_FILE"
  terraform -chdir="$DIR" init -input=false -reconfigure
fi
