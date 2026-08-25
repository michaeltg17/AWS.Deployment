#!/usr/bin/env sh
# Run on the k3s CONTROL node (ssh into it first):
#   scp setup-control-node.sh <user>@<control-ip>:~ && ssh <user>@<control-ip> 'sh ~/setup-control-node.sh'
#
# Installs: helm, ingress-nginx (hostNetwork, node :80/:443), default ingress class, rancher.
# Prints the rancher URL + admin token at the end.

set -eu

# vanilla helm does not auto-detect the k3s kubeconfig (k3s kubectl does)
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

wait_for_k3s() {
  echo "Waiting for k3s control plane..."
  i=0
  while [ "$i" -lt 60 ]; do
    if kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
      return 0
    fi
    i=$((i + 1))
    sleep 5
  done
  echo "ERROR: k3s not ready after 5 min. Check: journalctl -u k3s -n 50"
  return 1
}

install_helm() {
  command -v helm >/dev/null 2>&1 && return 0
  echo "Installing helm..."
  curl -fsSL https://get.helm.sh/helm-v3.16.4-linux-amd64.tar.gz | tar -xzf - -C /tmp
  mv /tmp/linux-amd64/helm /usr/local/bin/helm
  helm version --short
}

install_ingress_nginx() {
  echo "Installing ingress-nginx (hostNetwork, node :80/:443)..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  # clear any release left pending from a previously failed install
  if ! helm list --deployed -q --namespace ingress-nginx 2>/dev/null | grep -qx "ingress-nginx"; then
    helm uninstall ingress-nginx --namespace ingress-nginx --ignore-not-found >/dev/null 2>&1 || true
  fi
  # no load balancer: the controller runs in each node's host network (one per
  # node via DaemonSet) and binds the node's :80/:443 directly. Pod-level load
  # balancing still happens in-cluster (Services/iptables). Requires ports
  # 80/443 to be free on the nodes - nothing else uses them here (k3s runs on
  # 6443, traefik/servicelb are disabled).
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.kind=DaemonSet \
    --set controller.hostNetwork=true \
    --set controller.service.type=ClusterIP
  # later steps create Ingress resources; the admission webhook must be available
  kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s
}

set_default_ingress_class() {
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-class
  namespace: kube-system
data:
  ingress-class: "nginx"
EOF
}

install_rancher() {
  echo "Installing rancher..."
  helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
  helm repo update
  helm upgrade --install rancher rancher-latest/rancher \
    --namespace cattle-system --create-namespace \
    --set hostname=rancher.local \
    --set private_hostname=rancher.local \
    --set replicas=1 \
    --set ingress.tls.source=none \
    --set service.type=NodePort \
    --set service.nodePort=31591
  # cold boot (DB seed + catalog restore) on small nodes can outlive the
  # chart's default startup probe budget (12 x 10s) - widen it, then restart.
  # strategic merge (not plain merge): JSON merge patch would replace the
  # whole containers array and drop the image field.
  kubectl -n cattle-system patch deploy rancher --type strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"rancher","startupProbe":{"failureThreshold":60,"periodSeconds":15}}]}}}}'
  kubectl -n cattle-system delete pod -l app=rancher -n cattle-system --wait=false
  kubectl -n cattle-system wait --for=condition=ready pod -l app=rancher --timeout=900s
  echo "rancher is ready."
}

main() {
  wait_for_k3s
  install_helm
  install_ingress_nginx
  set_default_ingress_class
  install_rancher

  # rancher 2.15+ stores the first-boot admin password in bootstrap-secret
  # (older versions: rancher_set_password). Give seeding up to 2 min.
  TOKEN=""
  i=0
  while [ "$i" -lt 24 ] && [ -z "$TOKEN" ]; do
    TOKEN=$(kubectl -n cattle-system get secret bootstrap-secret \
      -o jsonpath='{.data.bootstrapPassword}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [ -z "$TOKEN" ]; then
      TOKEN=$(kubectl -n cattle-system get secret --field-selector type=rancher_set_password \
        -o jsonpath='{.items[0].data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    fi
    i=$((i + 1))
    sleep 5
  done
  # AL2023 defaults to IMDSv2 - a session token is required
  IMDS_TOK=$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 300" http://169.254.169.254/latest/api/token 2>/dev/null || true)
  PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOK}" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
  [ -n "$PUBLIC_IP" ] || PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)

  echo ""
  echo "============================================================"
  echo "  RANCHER:   http://${PUBLIC_IP}:31591  (NodePort, see 'kubectl -n cattle-system get svc rancher')"
  echo "  USER:      admin"
  echo "  TOKEN:     ${TOKEN}"
  echo "  APP URL:   http://${PUBLIC_IP}/  (after k8s/deploy.sh)"
  echo "  KUBECONFIG: /etc/rancher/k3s/k3s.yaml (copy to your machine)"
  echo "============================================================"
}

main
