#!/usr/bin/env bash
# Install Docker and run Jenkins LTS on Ubuntu (machine 1).
# Bind-mounts Jenkins home at the same host path so docker build/run from pipelines work.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash infra/setup-jenkins-host.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_HOME="${JENKINS_HOME:-/var/jenkins_home}"
JENKINS_IMAGE="${JENKINS_IMAGE:-testdockerregistry-jenkins:lts}"
JENKINS_NAME="${JENKINS_NAME:-jenkins}"
JENKINS_HTTP_PORT="${JENKINS_HTTP_PORT:-8080}"
TARGET_USER="${SUDO_USER:-${USER}}"

echo "==> Installing Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
else
  echo "Docker already installed: $(docker --version)"
fi

echo "==> Adding ${TARGET_USER} to docker group"
if id "${TARGET_USER}" >/dev/null 2>&1; then
  usermod -aG docker "${TARGET_USER}"
fi

systemctl enable --now docker

echo "==> Preparing ${JENKINS_HOME}"
mkdir -p "${JENKINS_HOME}"
chown 1000:1000 "${JENKINS_HOME}"

echo "==> Building Jenkins image (docker CLI + kubectl + plugins)"
if [[ ! -f "${SCRIPT_DIR}/jenkins/Dockerfile" ]]; then
  echo "Missing ${SCRIPT_DIR}/jenkins/Dockerfile — run this script from a clone of the repo." >&2
  exit 1
fi
docker build -t "${JENKINS_IMAGE}" "${SCRIPT_DIR}/jenkins"

DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"

if docker ps -a --format '{{.Names}}' | grep -qx "${JENKINS_NAME}"; then
  echo "==> Recreating ${JENKINS_NAME} with the new image (data in ${JENKINS_HOME} is kept)"
  docker rm -f "${JENKINS_NAME}" >/dev/null
fi

echo "==> Starting Jenkins on port ${JENKINS_HTTP_PORT}"
docker run -d \
  --name "${JENKINS_NAME}" \
  --restart unless-stopped \
  --group-add "${DOCKER_GID}" \
  -p "${JENKINS_HTTP_PORT}:8080" \
  -p 50000:50000 \
  -v "${JENKINS_HOME}:${JENKINS_HOME}" \
  -e "JENKINS_HOME=${JENKINS_HOME}" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${JENKINS_IMAGE}"

PASSWORD_FILE="${JENKINS_HOME}/secrets/initialAdminPassword"
echo "==> Waiting for Jenkins initial admin password"
for _ in $(seq 1 60); do
  if docker exec "${JENKINS_NAME}" test -f "${PASSWORD_FILE}" 2>/dev/null; then
    break
  fi
  sleep 2
done

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "Jenkins is running."
echo "  UI:  http://${HOST_IP:-<this-host>}:${JENKINS_HTTP_PORT}"
if docker exec "${JENKINS_NAME}" test -f "${PASSWORD_FILE}" 2>/dev/null; then
  echo "  Unlock password:"
  docker exec "${JENKINS_NAME}" cat "${PASSWORD_FILE}"
else
  echo "  Password file not ready yet. Check logs: docker logs -f ${JENKINS_NAME}"
  echo "  Then: docker exec ${JENKINS_NAME} cat ${PASSWORD_FILE}"
fi
echo
echo "Next in the Jenkins UI:"
echo "  1. Unlock with the password above, create the admin user (plugins Git, GitHub,"
echo "     Docker Pipeline, Kubernetes CLI are already in the image)."
echo "  2. Add credentials: dockerhub (username + Access Token), kubeconfig (secret file)"
echo
echo "Open firewall TCP ${JENKINS_HTTP_PORT} toward you. This host must reach GitHub, Docker Hub, and k3s :6443."
echo "Log out and back in (or: newgrp docker) so ${TARGET_USER} can run docker without sudo."
