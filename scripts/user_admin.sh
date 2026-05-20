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
    ensure_linux_user "${admin_user}" || fail "Could not create user ${admin_user}."
fi

ensure_user_in_sudo "${admin_user}" || fail "Could not add ${admin_user} to sudo."
ensure_user_in_group "${admin_user}" "${SERVER_ADMIN_GROUP}" || fail "Could not add ${admin_user} to ${SERVER_ADMIN_GROUP}."

if confirm "Set or update local password for ${admin_user}?"; then
    passwd "${admin_user}"
fi

if confirm "Ensure SSH AllowUsers includes ${admin_user}?"; then
    ensure_sshd_allow_user "${admin_user}" || fail "Could not update SSH AllowUsers for ${admin_user}."
fi

ok "Admin user is prepared: ${admin_user}"
info "The user may need to log out and back in before new group membership applies."
