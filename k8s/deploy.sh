#!/usr/bin/env bash
# Deploys the app stack to the current kubectl context.
#
#   ./deploy.sh dev
#
# Reads:
#   environments/<env>.env             (DOMAIN, image tags, API_URL)
#   environments/<env>.secrets.env    (DB_PASSWORD, IMAGE_API_KEY - NOT committed)
#
# Requires: kubectl with context = the k3s cluster, helm (for bootstrap only).

set -euo pipefail

ENV_NAME="${1:-dev}"
K8S_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$K8S_DIR/environments/$ENV_NAME.env"
SECRETS_FILE="$K8S_DIR/environments/$ENV_NAME.secrets.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: missing $ENV_FILE"; exit 1; }
[ -f "$SECRETS_FILE" ] || { echo "ERROR: missing $SECRETS_FILE (copy .secrets.env.example and fill in values)"; exit 1; }

# shellcheck disable=SC1090
source "$ENV_FILE"
# shellcheck disable=SC1090
source "$SECRETS_FILE"

: "${DOMAIN:?set DOMAIN (node public IP or domain) in $ENV_FILE}"
: "${API_URL:?set API_URL in $ENV_FILE}"
: "${API_IMAGE_TAG:?set API_IMAGE_TAG in $ENV_FILE}"
: "${REACT_IMAGE_TAG:?set REACT_IMAGE_TAG in $ENV_FILE}"
: "${MIGRATIONS_IMAGE_TAG:?set MIGRATIONS_IMAGE_TAG in $ENV_FILE}"
: "${DB_PASSWORD:?set DB_PASSWORD in $SECRETS_FILE}"
: "${IMAGE_API_KEY:?set IMAGE_API_KEY in $SECRETS_FILE}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

render() {
  local f
  for f in "$@"; do
    sed \
      -e "s|__DOMAIN__|${DOMAIN}|g" \
      -e "s|__API_URL__|${API_URL}|g" \
      -e "s|__API_IMAGE_TAG__|${API_IMAGE_TAG}|g" \
      -e "s|__REACT_IMAGE_TAG__|${REACT_IMAGE_TAG}|g" \
      -e "s|__MIGRATIONS_IMAGE_TAG__|${MIGRATIONS_IMAGE_TAG}|g" \
      -e "s|__DB_PASSWORD__|${DB_PASSWORD}|g" \
      -e "s|__IMAGE_API_KEY__|${IMAGE_API_KEY}|g" \
      "$f" > "$TMP/$(basename "$f")"
  done
}

apply() {
  kubectl apply -f "$TMP/$1"
  echo "  applied $1"
}

render "$K8S_DIR"/*.yaml

# K8s >= 1.33 rejects IP addresses in ingress host (must be a DNS name).
# IP-based envs (dev) fall back to a catch-all rule by dropping the host.
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # keep the YAML list item, drop only the host value
  sed -i 's|^[[:space:]]*- host:.*$|    -|' "$TMP/ingress.yaml"
fi

echo "==> namespace"
apply namespace.yaml

echo "==> secrets"
apply secrets.yaml

echo "==> postgresql"
apply postgresql.yaml
kubectl -n app wait --for=condition=ready pod -l app=postgresql --timeout=180s

echo "==> migrations"
apply migrations-job.yaml
if ! kubectl -n app wait --for=condition=complete job/migrations --timeout=300s; then
  echo "ERROR: migrations job failed. Last logs:"
  kubectl -n app logs job/migrations --tail=50 || true
  exit 1
fi

echo "==> api"
apply api.yaml
kubectl -n app wait --for=condition=ready pod -l app=api --timeout=180s || true

echo "==> react"
apply react.yaml
kubectl -n app wait --for=condition=ready pod -l app=react --timeout=180s || true

echo "==> ingress"
apply ingress.yaml

echo ""
echo "============================================================"
  echo "  App:      http://${DOMAIN}:30080/"
  echo "  API:      http://${DOMAIN}:30080/api/  (via ingress)"
echo "  Rancher:  http://<control-ip>:3080"
echo "============================================================"
echo ""
echo "Quick check:"
  echo "  curl -s http://${DOMAIN}:30080/api/ | head"
echo "  kubectl -n app get pods,svc,ingress"
