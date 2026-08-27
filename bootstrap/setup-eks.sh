#!/usr/bin/env bash
# One-time bootstrap for an EKS environment (run AFTER `terraform apply`):
#   1. point kubectl at the cluster (aws eks update-kubeconfig)
#   2. wait for the worker nodes to be Ready
#   3. install the AWS Load Balancer Controller (it creates the public ALB
#      from k8s/ingress.yaml when the app is deployed)
#
# Usage (from the repo root, Git Bash / Linux / macOS):
#   bash bootstrap/setup-eks.sh [env]     # default: dev
#
# Reads cluster details from terraform/environments/<env> outputs. Override
# with CLUSTER_NAME / AWS_REGION / VPC_ID / ALB_CONTROLLER_ROLE_ARN if needed.

set -euo pipefail

ENV_NAME="${1:-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV_NAME"

[ -d "$TF_DIR" ] || { echo "ERROR: missing $TF_DIR"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found in PATH"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH"; exit 1; }

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }

CLUSTER_NAME="${CLUSTER_NAME:-$(tfout cluster_name)}"
AWS_REGION="${AWS_REGION:-$(tfout region)}"
VPC_ID="${VPC_ID:-$(tfout vpc_id)}"
ALB_CONTROLLER_ROLE_ARN="${ALB_CONTROLLER_ROLE_ARN:-$(tfout alb_controller_role_arn)}"

HELM_VERSION="3.16.4"
# Pin the chart for reproducible bootstraps. (Chart 1.x = controller v2.x;
# chart 1.17.1 -> controller v2.17.1.)
ALB_CONTROLLER_CHART_VERSION="1.17.1"

echo "==> waiting for cluster ${CLUSTER_NAME} to be active (${AWS_REGION})"
aws eks wait cluster-active --name "$CLUSTER_NAME" --region "$AWS_REGION"

echo "==> updating kubeconfig (alias: ${CLUSTER_NAME})"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --alias "$CLUSTER_NAME" --region "$AWS_REGION"

echo "==> waiting for worker nodes to be Ready"
kubectl wait --for=condition=Ready node --all --timeout=600s

install_helm() {
  command -v helm >/dev/null 2>&1 && return 0
  echo "==> installing helm v${HELM_VERSION}"
  local tmp
  tmp="$(mktemp -d)"
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    msys* | cygwin* | mingw* | windows*)
      curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-windows-amd64.zip" -o "$tmp/helm.zip"
      unzip -q -j "$tmp/helm.zip" helm.exe -d "$tmp"
      ;;
    *)
      curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar -xzf - -C "$tmp"
      ;;
  esac
  chmod +x "$tmp/helm"* 2>/dev/null || true
  HELM_BIN="$tmp/helm"
  [ -f "$tmp/helm.exe" ] && HELM_BIN="$tmp/helm.exe"
  HELM_DIR="$(dirname "$HELM_BIN")"
  export PATH="$HELM_DIR:$PATH"
  helm version --short
}

install_helm

echo "==> installing aws-load-balancer-controller (chart v${ALB_CONTROLLER_CHART_VERSION})"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null 2>&1 || true
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system --create-namespace \
  --version "$ALB_CONTROLLER_CHART_VERSION" \
  --set "clusterName=${CLUSTER_NAME}" \
  --set "region=${AWS_REGION}" \
  --set "vpcId=${VPC_ID}" \
  --set "serviceAccount.create=true" \
  --set "serviceAccount.name=aws-load-balancer-controller" \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${ALB_CONTROLLER_ROLE_ARN}" \
  --set "ingressClass=alb"

echo "==> waiting for the controller pods to be Ready"
kubectl -n kube-system wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=300s

echo ""
echo "============================================================"
echo "  Cluster:   ${CLUSTER_NAME} (${AWS_REGION})"
echo "  KubeCtx:   ${CLUSTER_NAME}"
echo "  ALB ctrl:  ready (it creates the public ALB from k8s/ingress.yaml)"
echo ""
echo "  Next:      cd k8s && ./deploy.sh ${ENV_NAME}"
echo "============================================================"
