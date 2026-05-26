#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root

# This script establishes the baseline that later scripts assume exists; keeping
# it explicit avoids hidden dependencies when rebuilding a server from scratch.
log_info "Preparing base system."

if [[ -r /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${ID}" != "debian" || "${VERSION_ID}" != "13" ]]; then
        log_warn "This toolkit targets Debian 13. Detected: ${PRETTY_NAME:-unknown}."
        prompt_confirm "Continue anyway?" || exit 1
    fi
fi

export DEBIAN_FRONTEND=noninteractive

log_info "Installing base packages."
log_info "software-properties-common is deliberately not installed because it is unnecessary for this Debian setup."
log_run apt-get update || log_fail "apt-get update failed. Package installation was not attempted. Check network, DNS and APT source configuration."
log_run apt-get install -y \
    apt-transport-https ca-certificates curl wget gnupg gpg lsb-release sudo \
    unzip zip git nano vim htop rsync acl openssl ufw fail2ban \
    unattended-upgrades apt-listchanges || log_fail "Base package installation failed. Base system was not marked complete; rerun after checking the APT log output."

log_info "Setting timezone to ${TIMEZONE}."
log_run timedatectl set-timezone "${TIMEZONE}" || log_fail "Could not set timezone to ${TIMEZONE}. Check TIMEZONE in config.sh."

log_info "Ensuring server admin group exists: ${SERVER_ADMIN_GROUP}."
if user_system_group_exists "${SERVER_ADMIN_GROUP}"; then
    log_info "Group ${SERVER_ADMIN_GROUP} already exists."
else
    user_create_system_group "${SERVER_ADMIN_GROUP}" || log_fail "Could not create server admin group: ${SERVER_ADMIN_GROUP}. No permissions were changed."
fi

log_info "Ensuring runtime directories exist."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_DIR}"     || log_fail "Could not create ${SERVER_ADMIN_DIR}. Later scripts were not run."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_LOG_DIR}"     || log_fail "Could not create log directory: ${SERVER_ADMIN_LOG_DIR}."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_BACKUP_DIR}"     || log_fail "Could not create backup directory: ${SERVER_ADMIN_BACKUP_DIR}."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_DOCS_DIR}"     || log_fail "Could not create docs directory: ${SERVER_ADMIN_DOCS_DIR}."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_MARIADB_DIR}"     || log_fail "Could not create MariaDB admin directory: ${SERVER_ADMIN_MARIADB_DIR}."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_STATE_DIR}"     || log_fail "Could not create state directory: ${SERVER_ADMIN_STATE_DIR}."

# Website private keys live here, so this directory is intentionally root-only.
install -d -o root -g root -m 700 "${SERVER_ADMIN_SSL_DIR}"     || log_fail "Could not create SSL certificate directory: ${SERVER_ADMIN_SSL_DIR}."

log_info "Setting shared toolkit root permissions."
file_set_server_admin_root_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}"     || log_fail "Could not set ${SERVER_ADMIN_DIR} to root:${SERVER_ADMIN_GROUP} 2770."

log_info "Setting shared toolkit directory permissions."
file_set_server_admin_directory_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}"     || log_fail "Could not set server-admin directory permissions. Some paths may be partially updated."

log_info "Making toolkit shell scripts executable by server-admin users."
file_set_server_admin_script_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}"     || log_fail "Could not set server-admin script permissions. Some paths may be partially updated."

log_info "Making toolkit non-script files group-maintainable."
file_set_server_admin_regular_file_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}"     || log_fail "Could not set server-admin file permissions. Some paths may be partially updated."

log_info "Restricting SSL certificate storage to root only."
file_harden_server_admin_ssl_directory "${SERVER_ADMIN_SSL_DIR}"     || log_fail "Could not harden SSL certificate directory: ${SERVER_ADMIN_SSL_DIR}."

# SSH is the first exposed service on a new host, so fail2ban is configured in
# the base layer rather than waiting for the web stack.
log_info "Configuring fail2ban for SSH brute-force protection."
tmp_fail2ban="$(mktemp)"
cat >"${tmp_fail2ban}" <<EOF
$(file_managed_header "core_base_system.sh")
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
findtime = 10m
bantime = 1h
EOF

file_write_managed /etc/fail2ban/jail.d/sshd.local 0644 root:root "${tmp_fail2ban}" \
    || log_fail "Could not write fail2ban SSH jail config."

# Restart after writing the managed jail so reruns converge on the desired
# runtime state instead of merely changing files on disk.
svc_enable_now fail2ban || log_fail "Could not enable fail2ban. SSH jail config was written, but the service was not started."
svc_restart fail2ban || log_fail "Could not restart fail2ban after writing SSH jail config. Check the fail2ban log and generated jail file."

# Security updates are deliberately narrow and opt-in via config because this is
# a personal hosting box, not an unattended general package-upgrade system.
if [[ "${ENABLE_UNATTENDED_SECURITY_UPDATES}" == "yes" ]]; then
    log_info "Configuring unattended upgrades for Debian security updates only."

    tmp_auto_upgrades="$(mktemp)"
    cat >"${tmp_auto_upgrades}" <<EOF
$(file_managed_header "core_base_system.sh")
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    tmp_security_upgrades="$(mktemp)"
    cat >"${tmp_security_upgrades}" <<EOF
$(file_managed_header "core_base_system.sh")
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
EOF

    file_write_managed /etc/apt/apt.conf.d/20auto-upgrades 0644 root:root "${tmp_auto_upgrades}" \
        || log_fail "Could not write unattended-upgrades periodic config."

    file_write_managed /etc/apt/apt.conf.d/51security-only-unattended-upgrades 0644 root:root "${tmp_security_upgrades}" \
        || log_fail "Could not write unattended-upgrades security-only config."

    svc_enable_now unattended-upgrades || log_fail "Could not enable unattended-upgrades. Config files were written but the service state was not changed."
else
    log_info "Unattended security updates disabled by config."
fi

state_write_base_system_complete_marker || log_fail "Could not write base system completion marker. Later scripts will still refuse to run until this succeeds."

log_ok "Base system setup complete."
