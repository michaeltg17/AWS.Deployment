#!/usr/bin/env bash
# Deploys the app stack to the current kubectl context.
#
#   ./deploy.sh dev
#
# Reads:
#   environments/<env>.env             (API_URL, IMAGE_API_URL, RDS_ENDPOINT, DB_USER, image tags)
#   environments/<env>.secrets.env    (DB_PASSWORD, IMAGE_API_KEY - NOT committed)
#
# Requires: kubectl pointed at the EKS cluster (aws eks update-kubeconfig).
# The database is RDS (created by terraform) - there is no in-cluster PG.

set -euo pipefail

ENV_NAME="${1:-dev}"
K8S_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$K8S_DIR/environments/$ENV_NAME.env"
SECRETS_FILE="$K8S_DIR/environments/$ENV_NAME.secrets.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: missing $ENV_FILE (copy $ENV_NAME.env.example to $ENV_FILE and fill in values)"; exit 1; }
[ -f "$SECRETS_FILE" ] || { echo "ERROR: missing $SECRETS_FILE (copy .secrets.env.example and fill in values)"; exit 1; }

# Strip \r so CRLF (Windows) env files cannot smuggle a carriage return into
# a value, which would corrupt the rendered YAML.
# shellcheck disable=SC1090
source <(tr -d '\r' < "$ENV_FILE")
# shellcheck disable=SC1090
source <(tr -d '\r' < "$SECRETS_FILE")

: "${API_URL:?set API_URL in $ENV_FILE}"
: "${IMAGE_API_URL:?set IMAGE_API_URL in $ENV_FILE}"
: "${RDS_ENDPOINT:?set RDS_ENDPOINT in $ENV_FILE (terraform output -raw rds_endpoint)}"
: "${DB_USER:?set DB_USER in $ENV_FILE (terraform output -raw db_user)}"
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
      -e "s|__API_URL__|${API_URL}|g" \
      -e "s|__IMAGE_API_URL__|${IMAGE_API_URL}|g" \
      -e "s|__RDS_ENDPOINT__|${RDS_ENDPOINT}|g" \
      -e "s|__DB_USER__|${DB_USER}|g" \
      -e "s|__API_IMAGE_TAG__|${API_IMAGE_TAG}|g" \
      -e "s|__REACT_IMAGE_TAG__|${REACT_IMAGE_TAG}|g" \
      -e "s|__MIGRATIONS_IMAGE_TAG__|${MIGRATIONS_IMAGE_TAG}|g" \
      -e "s|__DB_PASSWORD__|${DB_PASSWORD}|g" \
      -e "s|__IMAGE_API_KEY__|${IMAGE_API_KEY}|g" \
      "$f" > "$TMP/$(basename "$f")"
  done
}

apply() {
  # --validate=false: server-side OpenAPI validation can transiently fail to
  # download the schema from the EKS API server; manifests are already checked
  # by kubeconform in CI, so skip the redundant server-side validation.
  kubectl apply --validate=false -f "$TMP/$1"
  echo "  applied $1"
}

render "$K8S_DIR"/*.yaml

echo "==> namespace"
apply namespace.yaml

echo "==> secrets"
apply secrets.yaml

echo "==> migrations (runs against RDS at ${RDS_ENDPOINT})"
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

echo "==> ingress (the ALB controller creates the public ALB from this)"
apply ingress.yaml

# The controller publishes the ALB DNS name on the Ingress status.
ALB_DNS=""
for _ in $(seq 1 30); do
  ALB_DNS="$(kubectl -n app get ingress app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$ALB_DNS" ] && break
  sleep 6
done

echo ""
echo "============================================================"
echo "  App:      http://${ALB_DNS:-<ALB DNS not published yet>}/"
echo "  API:      http://${ALB_DNS:-<ALB DNS not published yet>}/api/  (via ALB)"
echo "============================================================"
echo ""
echo "Quick check:"
echo "  curl -s http://${ALB_DNS}/api/ | head"
echo "  kubectl -n app get pods,svc,ingress"
