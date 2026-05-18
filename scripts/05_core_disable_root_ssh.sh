#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# DISABLE ROOT SSH
#
# This is intentionally separate from base SSH hardening. It should only be run
# after confirming the configured admin user can SSH in and use sudo.
###############################################################################

warn "This disables SSH login for root."
warn "Before continuing, confirm from a separate terminal:"
warn "  ssh ${ADMIN_USER}@your-server"
warn "  sudo -v"
warn "Keep your current root session open while testing."

read -rp "Type DISABLE_ROOT to continue: " CONFIRM

if [[ "${CONFIRM}" != "DISABLE_ROOT" ]]; then
    info "Aborted."
    exit 0
fi

backup_file /etc/ssh/sshd_config

if grep -Eq "^[#[:space:]]*PermitRootLogin[[:space:]]+" /etc/ssh/sshd_config; then
    sed -i -E 's|^[#[:space:]]*PermitRootLogin[[:space:]]+.*|PermitRootLogin no|' /etc/ssh/sshd_config
else
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

info "Validating SSH configuration before reload."
run /usr/sbin/sshd -t
run systemctl reload ssh

ok "Root SSH login disabled."
