#!/usr/bin/env bash
set -euo pipefail

echo "========================================="
echo "  Running CI"
echo "========================================="

echo
echo "[1/5] Terraform format check"
(
  cd terraform
  terraform fmt -check -recursive
)
echo "OK: terraform fmt"

echo
echo "[2/5] Terraform validate"
(
  cd terraform/environments/dev
  # Drop any locally-initialized .terraform: it remembers the S3 backend,
  # and init -backend=false would try to contact it (CI has no AWS creds).
  rm -rf .terraform
  terraform init -backend=false -input=false
  terraform validate
)
echo "OK: terraform validate"

echo
echo "[3/5] Shellcheck"
shellcheck --severity=warning bootstrap/*.sh k8s/deploy.sh ci.sh ci-docker.sh
echo "OK: shellcheck"

echo
echo "[4/5] Parse YAML manifests"
python3 -c 'import yaml, glob; files = sorted(glob.glob("k8s/*.yaml")); [print("OK:", f, len(list(yaml.safe_load_all(open(f, encoding="utf-8")))), "docs") for f in files]; print("parsed", len(files), "files")'

echo
echo "[5/5] Validate k8s manifests (kubeconform)"
kubeconform -strict -summary -ignore-missing-schemas k8s/*.yaml

echo
echo "========================================="
echo "  All CI checks passed!"
echo "========================================="
