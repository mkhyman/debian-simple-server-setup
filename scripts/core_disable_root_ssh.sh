#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

# Root SSH lockout is intentionally separate from base setup because it is one
# of the few changes that can make remote recovery awkward if done prematurely.
warn "This disables SSH login for root."
warn "Before continuing, confirm from a separate terminal that an admin user can SSH in and use sudo."

read -rp "Admin user already tested with SSH and sudo: " tested_user

if ! validate_linux_username "${tested_user}"; then
    fail "Invalid Linux username: ${tested_user}"
fi

linux_user_exists "${tested_user}" || fail "User does not exist: ${tested_user}"

if ! id -nG "${tested_user}" | tr ' ' '\n' | grep -qx sudo; then
    fail "User ${tested_user} is not in sudo group."
fi

read -rp "Type DISABLE_ROOT to continue: " typed
[[ "${typed}" == "DISABLE_ROOT" ]] || { info "Aborted."; exit 0; }

# Back up before editing and validate before reload; SSH configuration mistakes
# are high-impact because they can remove the only remote access path.
backup_file /etc/ssh/sshd_config || fail "Could not back up sshd_config."

if grep -Eq "^[#[:space:]]*PermitRootLogin[[:space:]]+" /etc/ssh/sshd_config; then
    sed -i -E 's|^[#[:space:]]*PermitRootLogin[[:space:]]+.*|PermitRootLogin no|' /etc/ssh/sshd_config
else
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

reload_sshd_safely || fail "Could not validate and reload ssh."

ok "Root SSH login disabled."
