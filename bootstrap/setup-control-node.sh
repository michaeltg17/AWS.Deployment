#!/usr/bin/env sh
# Run on the k3s CONTROL node (ssh into it first):
#   scp setup-control-node.sh <user>@<control-ip>:~ && ssh <user>@<control-ip> 'sh ~/setup-control-node.sh'
#
# Installs: helm, ingress-nginx (NodePort), default ingress class, rancher.
# Prints the rancher URL + admin token at the end.

set -eu

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
  echo "Installing ingress-nginx (NodePort 80/443)..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=80 \
    --set controller.service.nodePorts.https=443
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
  helm repo add rancher-latest https://releases.rancher.com/charts
  helm repo update
  helm upgrade --install rancher rancher-latest/rancher \
    --namespace cattle-system --create-namespace \
    --set hostname=rancher.local \
    --set private_hostname=rancher.local \
    --set replicas=1 \
    --set ingress.tls.source=none \
    --set service.type=NodePort \
    --set service.nodePort=3080
  kubectl -n cattle-system wait --for=condition=ready pod -l app=rancher --timeout=420s
  echo "rancher is ready."
}

main() {
  wait_for_k3s
  install_helm
  install_ingress_nginx
  set_default_ingress_class
  install_rancher

  TOKEN=$(kubectl -n cattle-system get secret --field-selector type=rancher_set_password -o jsonpath='{.items[0].data.password}' | base64 -d)
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

  echo ""
  echo "============================================================"
  echo "  RANCHER:   http://${PUBLIC_IP}:3080"
  echo "  USER:      admin"
  echo "  TOKEN:     ${TOKEN}"
  echo "  APP URL:   http://${PUBLIC_IP}/  (after k8s/deploy.sh)"
  echo "  KUBECONFIG: /etc/rancher/k3s/k3s.yaml (copy to your machine)"
  echo "============================================================"
}

main
