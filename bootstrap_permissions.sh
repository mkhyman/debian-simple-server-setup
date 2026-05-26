#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/common.sh" "$@"
user_require_root

cat <<EOF
This script prepares the server-admin toolkit itself.
It does not configure the server.

It will:
  - create the configured server admin group if it does not already exist
  - make the toolkit directory group-maintainable by that group
  - make toolkit shell scripts executable
  - make toolkit non-script files group-readable/writable
  - leave SSL private key storage under ${SERVER_ADMIN_SSL_DIR} root-only

It will not:
  - install packages
  - create admin users
  - configure Apache, SSH, MariaDB, Redis or PHP-FPM
  - modify website directories
EOF

if ! prompt_confirm "Prepare toolkit permissions now?"; then
    log_info "Aborted. No toolkit permissions were changed."
    exit 0
fi

if user_system_group_exists "${SERVER_ADMIN_GROUP}"; then
    log_info "Server admin group already exists: ${SERVER_ADMIN_GROUP}."
else
    log_info "Creating server admin group: ${SERVER_ADMIN_GROUP}."
    user_create_system_group "${SERVER_ADMIN_GROUP}" \
        || log_fail "Could not create server admin group: ${SERVER_ADMIN_GROUP}. Toolkit permissions were not changed."
fi

log_info "Setting shared toolkit root permissions."
file_set_server_admin_root_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
    || log_fail "Could not set ${SERVER_ADMIN_DIR} to root:${SERVER_ADMIN_GROUP} 2770."

log_info "Setting shared toolkit directory permissions."
file_set_server_admin_directory_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
    || log_fail "Could not set server-admin directory permissions. Some paths may have been partially changed."

log_info "Making toolkit shell scripts executable by server-admin users."
file_set_server_admin_script_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
    || log_fail "Could not set server-admin script permissions. Some paths may have been partially changed."

log_info "Making toolkit non-script files group-maintainable."
file_set_server_admin_regular_file_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
    || log_fail "Could not set server-admin file permissions. Some paths may have been partially changed."

log_info "Restricting SSL certificate storage to root only."
file_harden_server_admin_ssl_directory "${SERVER_ADMIN_SSL_DIR}" \
    || log_fail "Could not harden SSL certificate storage: ${SERVER_ADMIN_SSL_DIR}."

log_ok "Toolkit permissions prepared."
