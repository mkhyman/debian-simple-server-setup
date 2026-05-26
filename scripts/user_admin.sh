#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

read -rp "Admin username to create/manage: " admin_user

if ! user_validate_system_username "${admin_user}"; then
    log_fail "Invalid Linux username: ${admin_user}"
fi

if user_system_user_exists "${admin_user}"; then
    log_info "Admin user found: ${admin_user}"
    prompt_confirm "Continue managing this existing user?" || exit 0
else
    log_warn "Admin user does not currently exist: ${admin_user}"
    prompt_confirm "Create this admin user?" || exit 0
    log_info "Creating admin user: ${admin_user}."
    user_create_system_user "${admin_user}" || log_fail "Could not create admin user ${admin_user}. No sudo or SSH changes were applied for this user."
fi

if user_system_user_in_group "${admin_user}" "sudo"; then
    log_info "${admin_user} is already in sudo."
else
    log_info "Adding ${admin_user} to sudo."
    user_add_to_group "${admin_user}" "sudo" || log_fail "Could not add ${admin_user} to sudo. SSH access was not changed by this script."
fi

if user_system_user_in_group "${admin_user}" "${SERVER_ADMIN_GROUP}"; then
    log_info "${admin_user} is already in ${SERVER_ADMIN_GROUP}."
else
    log_info "Adding ${admin_user} to ${SERVER_ADMIN_GROUP}."
    user_add_to_group "${admin_user}" "${SERVER_ADMIN_GROUP}" || log_fail "Could not add ${admin_user} to ${SERVER_ADMIN_GROUP}. Toolkit file access may not work for this user."
fi

if prompt_confirm "Set or update local password for ${admin_user}?"; then
    passwd "${admin_user}" || log_fail "Password update failed for ${admin_user}. Continuing would leave the account in an unknown login state."
fi

if prompt_confirm "Ensure SSH AllowUsers includes ${admin_user}?"; then
    ssh_ensure_daemon_allow_user "${admin_user}" || log_fail "Could not update SSH AllowUsers for ${admin_user}. SSH was not reloaded unless config validation succeeded."
fi

log_ok "Admin user is prepared: ${admin_user}"
log_info "The user may need to log out and back in before new group membership applies."
