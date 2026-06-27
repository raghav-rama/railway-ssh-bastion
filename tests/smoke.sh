#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="railway-ssh-bastion:test"
CONTAINER_NAME="railway-ssh-bastion-smoke"
TMP_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

docker build -t "${IMAGE_TAG}" "${ROOT_DIR}"

missing_env_log="${TMP_DIR}/missing-env.log"
if docker run --rm --name "${CONTAINER_NAME}" "${IMAGE_TAG}" >"${missing_env_log}" 2>&1; then
  echo "expected container startup to fail without required env vars" >&2
  exit 1
fi

grep -q "ADMIN_AUTHORIZED_KEYS is required" "${missing_env_log}"

ssh-keygen -q -t ed25519 -N "" -f "${TMP_DIR}/admin" >/dev/null
ssh-keygen -q -t ed25519 -N "" -f "${TMP_DIR}/laptop" >/dev/null

docker run -d \
  --rm \
  --name "${CONTAINER_NAME}" \
  -e PORT=18080 \
  -e ADMIN_AUTHORIZED_KEYS="$(cat "${TMP_DIR}/admin.pub")" \
  -e LAPTOP_TUNNEL_PUBLIC_KEY="$(cat "${TMP_DIR}/laptop.pub")" \
  -p 18080:18080 \
  -p 2222:2222 \
  "${IMAGE_TAG}" >/dev/null

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:18080/health >/dev/null; then
    break
  fi
  sleep 1
done

curl -fsS http://127.0.0.1:18080/health | grep -q "ok"

ssh \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${TMP_DIR}/known_hosts" \
  -i "${TMP_DIR}/admin" \
  -p 2222 \
  railway@127.0.0.1 true

if ssh \
  -o BatchMode=yes \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=0 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile="${TMP_DIR}/known_hosts" \
  -p 2222 \
  railway@127.0.0.1 true; then
  echo "password authentication should be disabled" >&2
  exit 1
fi

docker exec "${CONTAINER_NAME}" sh -lc \
  "grep -F 'restrict,port-forwarding,permitlisten=\"localhost:2201\",no-pty,no-user-rc,no-X11-forwarding $(cat "${TMP_DIR}/laptop.pub")' /home/railway/.ssh/authorized_keys"
