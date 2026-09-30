#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Rulează cu sudo: sudo bash infra/setup-k8s-host.sh [IP-ul-acestei-mașini]" >&2
  exit 1
fi

K8S_IP="${1:-$(hostname -I | awk '{print $1}')}"

echo "==> Instalare k3s (un nod)"
if command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s; then
  echo "k3s e deja instalat și pornit"
else
  curl -sfL https://get.k3s.io | sh -
fi

echo "==> Aștept nod Ready"
for _ in $(seq 1 60); do
  if k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
    break
  fi
  sleep 2
done

k3s kubectl get nodes -o wide

KUBECONFIG_OUT="/root/kubeconfig-jenkins.yaml"
sed "s/127.0.0.1/${K8S_IP}/g" /etc/rancher/k3s/k3s.yaml > "${KUBECONFIG_OUT}"
chmod 600 "${KUBECONFIG_OUT}"

echo
echo "k3s e gata."
echo "  API: https://${K8S_IP}:6443"
echo "  Kubeconfig pentru Jenkins: ${KUBECONFIG_OUT}"
echo "  Copiază-l pe PC și încarcă-l în Jenkins ca credential Secret file, ID: kubeconfig"
echo "  După deploy, aplicația: http://${K8S_IP}:30080"
echo
echo "Firewall recomandat:"
echo "  ufw allow from <IP-JENKINS> to any port 6443 proto tcp"
echo "  ufw allow 30080/tcp"
echo "  ufw allow 80/tcp   # opțional, k3s ServiceLB"
