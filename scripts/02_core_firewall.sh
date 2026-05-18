#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# FIREWALL SETUP
#
# This script configures UFW without resetting existing rules. It only ensures
# the ports required by the agreed hosting model are present.
###############################################################################

info "Configuring UFW firewall."
info "Existing UFW rules are not reset, because this server may have manual rules."

run apt-get update
run apt-get install -y ufw

run ufw default deny incoming
run ufw default allow outgoing

run ufw allow "${SSH_PORT}/tcp" comment "SSH"
run ufw allow 80/tcp comment "HTTP redirect to HTTPS"
run ufw allow 443/tcp comment "HTTPS"
run ufw allow "${MARIADB_PORT}/tcp" comment "MariaDB SSL"

run ufw --force enable

info "Recording UFW status."
if [[ "${VERBOSE}" == "yes" ]]; then
    ufw status verbose | tee -a "${LOG_FILE}"
else
    ufw status verbose >>"${LOG_FILE}" 2>&1
fi

ok "Firewall configured."
