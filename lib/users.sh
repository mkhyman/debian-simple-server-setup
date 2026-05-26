#!/usr/bin/env bash
###############################################################################
# USERS HELPERS
#
# Reusable Linux user/group primitives. These functions avoid presentation;
# scripts decide whether missing users/groups are OK, warnings, failures or
# repair opportunities.
###############################################################################

user_validate_system_username() {
    local username="$1"
    [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}


user_system_user_exists() {
    local username="$1"
    id "${username}" >/dev/null 2>&1
}


user_system_group_exists() {
    local group_name="$1"
    getent group "${group_name}" >/dev/null 2>&1
}


user_system_user_in_group() {
    local username="$1"
    local group_name="$2"

    id -nG "${username}" | tr ' ' '
' | grep -qx "${group_name}"
}


user_create_system_group() {
    local group_name="$1"
    groupadd --system "${group_name}"
}


user_create_system_user() {
    local username="$1"
    useradd -m -s /bin/bash "${username}"
}


user_add_to_group() {
    local username="$1"
    local group_name="$2"

    user_system_group_exists "${group_name}" || return 1
    usermod -aG "${group_name}" "${username}"
}


user_require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        cat >&2 <<EOF
[ERROR] This script must be run as root or via sudo.

Example:
  sudo ./${SCRIPT_NAME}.sh
EOF
        exit 1
    fi
}
