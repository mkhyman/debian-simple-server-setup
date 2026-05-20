#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

info "Configuring UFW firewall without resetting existing rules."

run apt-get update || fail "apt-get update failed."
run apt-get install -y ufw || fail "Could not install ufw."

run ufw default deny incoming || fail "Could not set incoming firewall default."
run ufw default allow outgoing || fail "Could not set outgoing firewall default."

run ufw allow "${SSH_PORT}/tcp" comment "SSH" || fail "Could not allow SSH."
run ufw allow 80/tcp comment "HTTP redirect to HTTPS" || fail "Could not allow HTTP."
run ufw allow 443/tcp comment "HTTPS" || fail "Could not allow HTTPS."
run ufw allow "${MARIADB_PORT}/tcp" comment "MariaDB SSL" || fail "Could not allow MariaDB."

run ufw --force enable || fail "Could not enable UFW."

ufw status verbose >>"${LOG_FILE}" 2>&1 || true
ok "Firewall configured."
