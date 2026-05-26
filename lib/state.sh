#!/usr/bin/env bash
###############################################################################
# STATE HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

state_base_system_complete() {
    [[ -f "${BASE_SYSTEM_COMPLETE_FILE}" ]]
}


state_write_base_system_complete_marker() {
    mkdir -p "${SERVER_ADMIN_STATE_DIR}" || return 1

    {
        echo "completed_at=$(date -Is)"
        echo "script=core_base_system.sh"
        echo "toolkit_version=${SERVER_SETUP_TOOLKIT_VERSION}"
    } > "${BASE_SYSTEM_COMPLETE_FILE}" || return 1

    chown root:"${SERVER_ADMIN_GROUP}" "${BASE_SYSTEM_COMPLETE_FILE}" || return 1
    chmod 660 "${BASE_SYSTEM_COMPLETE_FILE}" || return 1
}


state_require_base_system_complete() {
    if ! state_base_system_complete; then
        cat >&2 <<EOF
[ERROR] Base system setup has not been completed.

Run first:
  sudo ./scripts/core_base_system.sh

Or use:
  sudo ./run_server_setup.sh
EOF
        exit 1
    fi
}

