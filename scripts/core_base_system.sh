#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root

# This script establishes the baseline that later scripts assume exists; keeping
# it explicit avoids hidden dependencies when rebuilding a server from scratch.
info "Preparing base system."

if [[ -r /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${ID}" != "debian" || "${VERSION_ID}" != "13" ]]; then
        warn "This toolkit targets Debian 13. Detected: ${PRETTY_NAME:-unknown}."
        confirm "Continue anyway?" || exit 1
    fi
fi

export DEBIAN_FRONTEND=noninteractive

info "Installing base packages."
info "software-properties-common is deliberately not installed because it is unnecessary for this Debian setup."
run apt-get update || fail "apt-get update failed."
run apt-get install -y \
    apt-transport-https ca-certificates curl wget gnupg gpg lsb-release sudo \
    unzip zip git nano vim htop rsync acl openssl ufw fail2ban \
    unattended-upgrades apt-listchanges || fail "Base package installation failed."

info "Setting timezone to ${TIMEZONE}."
run timedatectl set-timezone "${TIMEZONE}" || fail "Could not set timezone."

info "Ensuring server admin group exists: ${SERVER_ADMIN_GROUP}."
if getent group "${SERVER_ADMIN_GROUP}" >/dev/null 2>&1; then
    info "Group ${SERVER_ADMIN_GROUP} already exists."
else
    run groupadd --system "${SERVER_ADMIN_GROUP}" || fail "Could not create ${SERVER_ADMIN_GROUP} group."
fi

info "Ensuring runtime directories exist."
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_DIR}"
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_LOG_DIR}"
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_BACKUP_DIR}"
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_DOCS_DIR}"
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_MARIADB_DIR}"
install -d -o root -g "${SERVER_ADMIN_GROUP}" -m 2770 "${SERVER_ADMIN_STATE_DIR}"

# Website private keys live here, so this directory is intentionally root-only.
install -d -o root -g root -m 700 "${SERVER_ADMIN_SSL_DIR}"

info "Hardening toolkit repository permissions."
find "${SERVER_ADMIN_DIR}" \
    -path "${SERVER_ADMIN_DIR}/.git" -prune -o \
    -path "${SERVER_ADMIN_SSL_DIR}" -prune -o \
    -type d -exec chgrp "${SERVER_ADMIN_GROUP}" {} + -exec chmod 2770 {} +

find "${SERVER_ADMIN_DIR}" \
    -path "${SERVER_ADMIN_DIR}/.git" -prune -o \
    -path "${SERVER_ADMIN_SSL_DIR}" -prune -o \
    -type f -name "*.sh" -exec chgrp "${SERVER_ADMIN_GROUP}" {} + -exec chmod 770 {} +

find "${SERVER_ADMIN_DIR}" \
    -path "${SERVER_ADMIN_DIR}/.git" -prune -o \
    -path "${SERVER_ADMIN_SSL_DIR}" -prune -o \
    -type f ! -name "*.sh" -exec chgrp "${SERVER_ADMIN_GROUP}" {} + -exec chmod 660 {} +

# SSH is the first exposed service on a new host, so fail2ban is configured in
# the base layer rather than waiting for the web stack.
info "Configuring fail2ban for SSH brute-force protection."
tmp_fail2ban="$(mktemp)"
cat >"${tmp_fail2ban}" <<EOF
$(managed_header "core_base_system.sh")
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
findtime = 10m
bantime = 1h
EOF

write_managed_file /etc/fail2ban/jail.d/sshd.local 0644 root:root "${tmp_fail2ban}" \
    || fail "Could not write fail2ban SSH jail config."

# Restart after writing the managed jail so reruns converge on the desired
# runtime state instead of merely changing files on disk.
service_enable_now fail2ban || fail "Could not enable fail2ban."
service_restart fail2ban || fail "Could not restart fail2ban."

# Security updates are deliberately narrow and opt-in via config because this is
# a personal hosting box, not an unattended general package-upgrade system.
if [[ "${ENABLE_UNATTENDED_SECURITY_UPDATES}" == "yes" ]]; then
    info "Configuring unattended upgrades for Debian security updates only."

    tmp_auto_upgrades="$(mktemp)"
    cat >"${tmp_auto_upgrades}" <<EOF
$(managed_header "core_base_system.sh")
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    tmp_security_upgrades="$(mktemp)"
    cat >"${tmp_security_upgrades}" <<EOF
$(managed_header "core_base_system.sh")
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
EOF

    write_managed_file /etc/apt/apt.conf.d/20auto-upgrades 0644 root:root "${tmp_auto_upgrades}" \
        || fail "Could not write unattended-upgrades periodic config."

    write_managed_file /etc/apt/apt.conf.d/51security-only-unattended-upgrades 0644 root:root "${tmp_security_upgrades}" \
        || fail "Could not write unattended-upgrades security-only config."

    service_enable_now unattended-upgrades || fail "Could not enable unattended-upgrades."
else
    info "Unattended security updates disabled by config."
fi

write_base_system_complete_marker || fail "Could not write base system completion marker."

ok "Base system setup complete."
