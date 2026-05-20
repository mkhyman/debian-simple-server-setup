#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

info "Configuring UFW firewall without resetting existing rules."

run apt-get update || fail "apt-get update failed. Firewall configuration was not changed."
run apt-get install -y ufw || fail "Could not install ufw. Firewall configuration was not changed."

run ufw default deny incoming || fail "Could not set UFW incoming default policy. UFW was not enabled by this script."
run ufw default allow outgoing || fail "Could not set UFW outgoing default policy. UFW was not enabled by this script."

run ufw allow "${SSH_PORT}/tcp" comment "SSH" || fail "Could not add SSH allow rule for port ${SSH_PORT}. UFW was not enabled by this script."
run ufw allow 80/tcp comment "HTTP redirect to HTTPS" || fail "Could not add HTTP allow rule. UFW was not enabled by this script."
run ufw allow 443/tcp comment "HTTPS" || fail "Could not add HTTPS allow rule. UFW was not enabled by this script."
run ufw allow "${MARIADB_PORT}/tcp" comment "MariaDB SSL" || fail "Could not add MariaDB allow rule for port ${MARIADB_PORT}. UFW was not enabled by this script."

run ufw --force enable || fail "Could not enable UFW. Rules may have been added, but the firewall activation failed."

ufw status verbose >>"${LOG_FILE}" 2>&1 || true
ok "Firewall configured."
