#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# BASE ADMIN + SSH SECURITY
#
# This script prepares the primary sudo/admin user and SSH hardening baseline.
# Root SSH login is deliberately left unchanged here so you do not lock yourself
# out before confirming the admin user can log in and use sudo.
###############################################################################

info "Preparing base admin/security setup."

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
run apt-get update
run apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg \
    gpg \
    lsb-release \
    sudo \
    unzip \
    zip \
    git \
    nano \
    vim \
    htop \
    rsync \
    acl \
    openssl \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges

info "Setting timezone to ${TIMEZONE}."
run timedatectl set-timezone "${TIMEZONE}"

if id "${ADMIN_USER}" &>/dev/null; then
    info "Admin user ${ADMIN_USER} already exists."
else
    info "Creating admin user ${ADMIN_USER}."
    run useradd -m -s /bin/bash "${ADMIN_USER}"
fi

info "Ensuring ${ADMIN_USER} is a member of sudo."
run usermod -aG sudo "${ADMIN_USER}"

if confirm "Set or update local sudo password for ${ADMIN_USER}?"; then
    passwd "${ADMIN_USER}"
fi

ADMIN_HOME="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)"
install -d -m 700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${ADMIN_HOME}/.ssh"

AUTHORIZED_KEYS="${ADMIN_HOME}/.ssh/authorized_keys"
touch "${AUTHORIZED_KEYS}"
chown "${ADMIN_USER}:${ADMIN_USER}" "${AUTHORIZED_KEYS}"
chmod 600 "${AUTHORIZED_KEYS}"

if [[ -f "${ADMIN_SSH_PUBLIC_KEY_FILE}" ]]; then
    info "Reading admin SSH public key from ${ADMIN_SSH_PUBLIC_KEY_FILE}."
    ADMIN_KEY="$(cat "${ADMIN_SSH_PUBLIC_KEY_FILE}")"
else
    echo
    echo "Paste the SSH public key for ${ADMIN_USER}."
    echo "Example: ssh-ed25519 AAAA... comment"
    read -rp "SSH public key: " ADMIN_KEY
fi

if [[ -n "${ADMIN_KEY}" ]]; then
    if grep -qxF "${ADMIN_KEY}" "${AUTHORIZED_KEYS}"; then
        info "SSH key already present for ${ADMIN_USER}."
    else
        echo "${ADMIN_KEY}" >> "${AUTHORIZED_KEYS}"
        ok "Added SSH key for ${ADMIN_USER}."
    fi
else
    warn "No SSH key supplied. Do not disable root login until key login works."
fi

warn "This will disable SSH password authentication."
warn "Root SSH login is not disabled by this script."
warn "Keep an existing root session open and test admin login from a new terminal."
confirm "Apply SSH key-only hardening now?" || {
    info "SSH hardening skipped."
    exit 0
}

backup_file /etc/ssh/sshd_config

set_sshd_option() {
    local key="$1"
    local value="$2"
    local file="/etc/ssh/sshd_config"

    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "${file}"; then
        sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "${file}"
    else
        printf '\n%s %s\n' "${key}" "${value}" >> "${file}"
    fi
}

set_sshd_option "PermitEmptyPasswords" "no"
set_sshd_option "PubkeyAuthentication" "yes"
set_sshd_option "PasswordAuthentication" "no"
set_sshd_option "KbdInteractiveAuthentication" "no"
set_sshd_option "MaxAuthTries" "3"

# Preserve any existing AllowUsers values. Replacing the list blindly could lock
# out another legitimate admin account.
if grep -Eq "^[[:space:]]*AllowUsers[[:space:]]+" /etc/ssh/sshd_config; then
    EXISTING="$(grep -E "^[[:space:]]*AllowUsers[[:space:]]+" /etc/ssh/sshd_config | tail -n1 | sed -E 's/^[[:space:]]*AllowUsers[[:space:]]+//')"
    if echo " ${EXISTING} " | grep -q " ${ADMIN_USER} "; then
        info "AllowUsers already includes ${ADMIN_USER}."
    else
        warn "Preserving existing AllowUsers and adding ${ADMIN_USER}."
        sed -i -E "s|^[[:space:]]*AllowUsers[[:space:]]+.*|AllowUsers ${EXISTING} ${ADMIN_USER}|" /etc/ssh/sshd_config
    fi
else
    echo "AllowUsers ${ADMIN_USER}" >> /etc/ssh/sshd_config
fi

info "Validating SSH configuration before reload."
run /usr/sbin/sshd -t
run systemctl reload ssh

info "Configuring fail2ban for SSH brute-force protection."
cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = %(sshd_log)s
maxretry = 3
findtime = 10m
bantime = 1h
EOF

run systemctl enable --now fail2ban
run systemctl restart fail2ban

if [[ "${ENABLE_UNATTENDED_SECURITY_UPDATES}" == "yes" ]]; then
    info "Configuring unattended upgrades for Debian security updates only."
    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    cat >/etc/apt/apt.conf.d/51security-only-unattended-upgrades <<'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
EOF

    run systemctl enable --now unattended-upgrades
else
    info "Unattended security updates disabled by config."
fi

ok "Base admin/security setup complete."
info "Next: open a new terminal and test: ssh ${ADMIN_USER}@your-server"
info "Then confirm sudo works: sudo -v"
