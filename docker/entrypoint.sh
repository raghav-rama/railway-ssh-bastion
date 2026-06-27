#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
}

render_caddyfile() {
  local target="/run/Caddyfile"
  sed "s/__PORT__/${PORT}/g" /etc/caddy/Caddyfile.template >"${target}"
}

write_authorized_keys() {
  local tmp_file
  tmp_file="$(mktemp)"

  printf '%s\n' "${ADMIN_AUTHORIZED_KEYS}" >>"${tmp_file}"
  printf 'restrict,port-forwarding,permitlisten="localhost:2201",no-pty,no-user-rc,no-X11-forwarding %s\n' \
    "${LAPTOP_TUNNEL_PUBLIC_KEY}" >>"${tmp_file}"

  awk 'NF' "${tmp_file}" >"${tmp_file}.clean"
  install -m 0600 -o railway -g railway "${tmp_file}.clean" /home/railway/.ssh/authorized_keys

  rm -f "${tmp_file}" "${tmp_file}.clean"
}

start_services() {
  caddy run --config /run/Caddyfile --adapter caddyfile &
  caddy_pid=$!

  /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config &
  sshd_pid=$!

  trap 'kill "${caddy_pid}" "${sshd_pid}" >/dev/null 2>&1 || true' TERM INT

  wait -n "${caddy_pid}" "${sshd_pid}"
  status=$?

  kill "${caddy_pid}" "${sshd_pid}" >/dev/null 2>&1 || true
  wait "${caddy_pid}" "${sshd_pid}" >/dev/null 2>&1 || true

  return "${status}"
}

require_env ADMIN_AUTHORIZED_KEYS
require_env LAPTOP_TUNNEL_PUBLIC_KEY

PORT="${PORT:-8080}"

if ! id -u railway >/dev/null 2>&1; then
  useradd --create-home --home-dir /home/railway --shell /bin/bash railway
fi

usermod -p "$(openssl passwd -6 "$(openssl rand -base64 48)")" railway

install -d -m 0700 -o railway -g railway /home/railway/.ssh
install -d -m 0755 /var/run/sshd /run

write_authorized_keys
render_caddyfile
ssh-keygen -A >/dev/null

start_services
