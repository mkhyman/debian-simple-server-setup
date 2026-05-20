#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

read -rp "Admin username to create/manage: " admin_user

if ! validate_linux_username "${admin_user}"; then
    fail "Invalid Linux username: ${admin_user}"
fi

if linux_user_exists "${admin_user}"; then
    info "Admin user found: ${admin_user}"
    confirm "Continue managing this existing user?" || exit 0
else
    warn "Admin user does not currently exist: ${admin_user}"
    confirm "Create this admin user?" || exit 0
    ensure_linux_user "${admin_user}" || fail "Could not create admin user ${admin_user}. No sudo or SSH changes were applied for this user."
fi

ensure_user_in_sudo "${admin_user}" || fail "Could not add ${admin_user} to sudo. SSH access was not changed by this script."
ensure_user_in_group "${admin_user}" "${SERVER_ADMIN_GROUP}" || fail "Could not add ${admin_user} to ${SERVER_ADMIN_GROUP}. Toolkit file access may not work for this user."

if confirm "Set or update local password for ${admin_user}?"; then
    passwd "${admin_user}" || fail "Password update failed for ${admin_user}. Continuing would leave the account in an unknown login state."
fi

if confirm "Ensure SSH AllowUsers includes ${admin_user}?"; then
    ensure_sshd_allow_user "${admin_user}" || fail "Could not update SSH AllowUsers for ${admin_user}. SSH was not reloaded unless config validation succeeded."
fi

ok "Admin user is prepared: ${admin_user}"
info "The user may need to log out and back in before new group membership applies."
