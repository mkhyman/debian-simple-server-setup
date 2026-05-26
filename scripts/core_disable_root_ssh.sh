#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

# Root SSH lockout is intentionally separate from base setup because it is one
# of the few changes that can make remote recovery awkward if done prematurely.
log_warn "This disables SSH login for root."
log_warn "Before continuing, prompt_confirm from a separate terminal that an admin user can SSH in and use sudo."

read -rp "Admin user already tested with SSH and sudo: " tested_user

if ! user_validate_system_username "${tested_user}"; then
    log_fail "Invalid Linux username: ${tested_user}"
fi

user_system_user_exists "${tested_user}" || log_fail "User does not exist: ${tested_user}"

if ! id -nG "${tested_user}" | tr ' ' '\n' | grep -qx sudo; then
    log_fail "User ${tested_user} is not in sudo group."
fi

read -rp "Type DISABLE_ROOT to continue: " typed
[[ "${typed}" == "DISABLE_ROOT" ]] || { log_info "Aborted."; exit 0; }

# Use the managed sshd_config.d fragment rather than editing Debian's main
# sshd_config. Root login policy is important enough to own explicitly, but not
# important enough to make future package upgrades harder to inspect.
ssh_ensure_daemon_root_login_disabled || log_fail "Could not disable root SSH login safely."

log_ok "Root SSH login disabled."
