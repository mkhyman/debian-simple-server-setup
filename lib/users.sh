#!/usr/bin/env bash
###############################################################################
# USERS HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
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

user_create_system_group() {
    local group_name="$1"

    log_run groupadd --system "${group_name}"
}


user_create_system_user() {
    local username="$1"

    log_run useradd -m -s /bin/bash "${username}"
}

user_ensure_system_user() {
    local username="$1"

    if user_system_user_exists "${username}"; then
        log_info "User already exists: ${username}"
        return 0
    fi

    user_create_system_user "${username}"
}


user_ensure_in_group() {
    local username="$1"
    local group_name="$2"

    user_system_group_exists "${group_name}" || return 1

    if id -nG "${username}" | tr ' ' '\n' | grep -qx "${group_name}"; then
        log_info "User ${username} is already in group ${group_name}."
        return 0
    fi

    log_run usermod -aG "${group_name}" "${username}"
}


user_ensure_in_sudo() {
    local username="$1"
    user_ensure_in_group "${username}" "sudo"
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

