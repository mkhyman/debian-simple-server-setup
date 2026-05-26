#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

log_info "Configuring UFW firewall without resetting existing rules."

log_run apt-get update || log_fail "apt-get update failed. Firewall configuration was not changed."
log_run apt-get install -y ufw || log_fail "Could not install ufw. Firewall configuration was not changed."

log_run ufw default deny incoming || log_fail "Could not set UFW incoming default policy. UFW was not enabled by this script."
log_run ufw default allow outgoing || log_fail "Could not set UFW outgoing default policy. UFW was not enabled by this script."

log_run ufw allow "${SSH_PORT}/tcp" comment "SSH" || log_fail "Could not add SSH allow rule for port ${SSH_PORT}. UFW was not enabled by this script."
log_run ufw allow 80/tcp comment "HTTP redirect to HTTPS" || log_fail "Could not add HTTP allow rule. UFW was not enabled by this script."
log_run ufw allow 443/tcp comment "HTTPS" || log_fail "Could not add HTTPS allow rule. UFW was not enabled by this script."
log_run ufw allow "${MARIADB_PORT}/tcp" comment "MariaDB SSL" || log_fail "Could not add MariaDB allow rule for port ${MARIADB_PORT}. UFW was not enabled by this script."

log_run ufw --force enable || log_fail "Could not enable UFW. Rules may have been added, but the firewall activation failed."

ufw status verbose >>"${LOG_FILE}" 2>&1 || true
log_ok "Firewall configured."
