#!/usr/bin/env bash
# Full teardown for an EKS environment (reverse of
# `terraform apply` -> bootstrap/setup-eks.sh -> k8s/deploy.sh):
#   1. delete the app namespace (the Ingress finalizer makes the ALB
#      controller delete the public ALB)
#   2. wait until the ALB and its ENIs/EIPs are gone from AWS
#   3. remove controller-created leftovers (k8s-* security groups)
#   4. uninstall the ALB controller
#   5. terraform destroy
#   6. verify nothing is left
#
# The ALB is NOT in the Terraform state: the AWS Load Balancer Controller
# creates it from k8s/ingress.yaml at deploy time. Running `terraform
# destroy` directly, without the k8s cleanup first, orphans the ALB, whose
# ENIs/EIPs then block the public subnets, the internet gateway and the VPC.
#
# Self-healing: if the cluster is already gone (e.g. `terraform destroy`
# was run directly), the script deletes the orphaned ALB and the k8s-*
# security groups via the aws CLI before finishing the destroy.
#
# Usage (from the repo root, Git Bash / Linux / macOS):
#   bash bootstrap/teardown.sh [env]     # default: dev
#
# Reads cluster details from terraform/environments/<env> outputs. Override
# with CLUSTER_NAME / AWS_REGION / VPC_ID if needed.

set -euo pipefail

ENV_NAME="${1:-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV_NAME"

[ -d "$TF_DIR" ] || { echo "ERROR: missing $TF_DIR"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found in PATH"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform not found in PATH"; exit 1; }

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }

CLUSTER_NAME="${CLUSTER_NAME:-$(tfout cluster_name)}"
AWS_REGION="${AWS_REGION:-$(tfout region)}"
VPC_ID="${VPC_ID:-$(tfout vpc_id)}"

ALB_GONE_TIMEOUT="${ALB_GONE_TIMEOUT:-900}"   # seconds to wait for ALB + ENI cleanup
NS_DELETE_TIMEOUT="${NS_DELETE_TIMEOUT:-300}" # seconds to wait for namespace deletion

cluster_reachable() {
  [ -n "$CLUSTER_NAME" ] && \
    aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1
}

alb_arns() {
  # ARNs of the ALBs the controller created in this VPC (empty when none).
  [ -n "$VPC_ID" ] || return 0
  local out
  out="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" --output text 2>/dev/null || true)"
  [ "$out" = "None" ] && out=""
  printf '%s' "$out"
}

no_albs() { [ -z "$(alb_arns)" ]; }

no_enis() {
  # The ALB's per-subnet ENIs (and their EIPs) must be released before the
  # public subnets and the VPC can be deleted.
  [ -n "$VPC_ID" ] || return 0
  local out
  out="$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo 0)"
  [ "$out" = "0" ]
}

ns_gone() { ! kubectl get ns app >/dev/null 2>&1; }

wait_for() {
  # wait_for <what> <timeout-s> <check-fn>: run the fn until it succeeds.
  local what="$1" timeout="$2" fn="$3" i=0
  until "$fn"; do
    i=$((i + 15))
    if [ "$i" -ge "$timeout" ]; then
      echo "ERROR: timed out after ${timeout}s waiting for: $what"
      exit 1
    fi
    echo "    waiting for: $what (${i}s elapsed)"
    sleep 15
  done
}

if cluster_reachable; then
  command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH (needed while the cluster is still up)"; exit 1; }

  echo "==> deleting the app namespace (the ALB controller removes the ALB from the Ingress)"
  if kubectl get ns app >/dev/null 2>&1; then
    kubectl delete ns app --timeout="${NS_DELETE_TIMEOUT}s"
  fi
  wait_for "the app namespace to be deleted" "$NS_DELETE_TIMEOUT" ns_gone
  wait_for "the ALB to be deleted from AWS" "$ALB_GONE_TIMEOUT" no_albs
  wait_for "the ALB's ENIs/EIPs to be released" "$ALB_GONE_TIMEOUT" no_enis

  if command -v helm >/dev/null 2>&1 && \
     helm list -n kube-system -q 2>/dev/null | grep -q '^aws-load-balancer-controller$'; then
    echo "==> uninstalling aws-load-balancer-controller"
    helm uninstall aws-load-balancer-controller -n kube-system
  fi
else
  echo "==> cluster '${CLUSTER_NAME:-<unknown>}' is not reachable; cleaning up orphaned AWS resources"
  if [ -n "$(alb_arns)" ]; then
    echo "==> deleting orphaned ALB(s) left behind by the controller"
    for arn in $(alb_arns); do
      aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$arn"
    done
    wait_for "the ALB to be deleted from AWS" "$ALB_GONE_TIMEOUT" no_albs
    wait_for "the ALB's ENIs/EIPs to be released" "$ALB_GONE_TIMEOUT" no_enis
  fi
fi

# The controller names its security groups k8s-*; Terraform-managed SGs use
# the resource-name prefix (e.g. template-dev-*), so the prefix is unambiguous.
if [ -n "$VPC_ID" ]; then
  sg_ids="$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?starts_with(GroupName, 'k8s-')].GroupId" --output text 2>/dev/null || true)"
  [ "$sg_ids" = "None" ] && sg_ids=""
  for sg in $sg_ids; do
    echo "==> deleting controller security group $sg"
    aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$sg"
  done
fi

echo "==> terraform destroy"
terraform -chdir="$TF_DIR" destroy -auto-approve

echo "==> verifying nothing is left"
leftover=0

if [ -n "$CLUSTER_NAME" ] && aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "  LEFTOVER: EKS cluster $CLUSTER_NAME"
  leftover=1
fi
if [ -n "$VPC_ID" ] && aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "  LEFTOVER: VPC $VPC_ID"
  leftover=1
fi
lb_names="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query "LoadBalancers[?starts_with(Name, 'k8s-')].Name" --output text 2>/dev/null || true)"
[ "$lb_names" = "None" ] && lb_names=""
if [ -n "$lb_names" ]; then
  echo "  LEFTOVER: ALB(s): $lb_names"
  leftover=1
fi
rds=""
if [ -n "$CLUSTER_NAME" ]; then
  rds="$(aws rds describe-db-instances --region "$AWS_REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier, '$CLUSTER_NAME')].DBInstanceIdentifier" --output text 2>/dev/null || true)"
  [ "$rds" = "None" ] && rds=""
fi
if [ -n "$rds" ]; then
  echo "  LEFTOVER: RDS instance(s): $rds"
  leftover=1
fi

if [ "$leftover" -eq 0 ]; then
  echo "OK: nothing left (cluster, VPC, ALB, RDS all gone)"
else
  echo "ERROR: leftovers remain - see above"
  exit 1
fi
