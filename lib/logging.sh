#!/usr/bin/env bash
###############################################################################
# LOGGING HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################


log_init() {
    mkdir -p "${SERVER_ADMIN_LOG_DIR}"
    LOG_FILE="${SERVER_ADMIN_LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
    touch "${LOG_FILE}"
    chmod 660 "${LOG_FILE}" 2>/dev/null || true
}

log_info() {
    echo "[INFO] $*"
    echo "[INFO] $*" >>"${LOG_FILE}"
}


log_warn() {
    echo "[WARN] $*"
    echo "[WARN] $*" >>"${LOG_FILE}"
}


log_ok() {
    echo "[OK] $*"
    echo "[OK] $*" >>"${LOG_FILE}"
}


log_fail() {
    echo "[ERROR] $*" >&2
    echo "[ERROR] $*" >>"${LOG_FILE}"
    echo
    echo "[ERROR] Full log: ${LOG_FILE}" >&2
    echo "[ERROR] Last 40 log lines:" >&2
    tail -n 40 "${LOG_FILE}" >&2 || true
    exit 1
}


log_run() {
    log_info "Running: $*"

    if [[ "${VERBOSE}" == "yes" ]]; then
        "$@" 2>&1 | tee -a "${LOG_FILE}"
        local rc=${PIPESTATUS[0]}
        [[ "${rc}" -eq 0 ]] || return "${rc}"
    else
        "$@" >>"${LOG_FILE}" 2>&1 || return "$?"
    fi
}

