#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

MH_CORE_HC_PASS_COUNT=0
MH_CORE_HC_WARN_COUNT=0
MH_CORE_HC_FAIL_COUNT=0

health_ok() {
    ok "$*"
    MH_CORE_HC_PASS_COUNT=$((MH_CORE_HC_PASS_COUNT+1))
}

health_warn() {
    warn "$*"
    MH_CORE_HC_WARN_COUNT=$((MH_CORE_HC_WARN_COUNT+1))
}

health_fail() {
    echo "[FAIL] $*"
    echo "[FAIL] $*" >>"${LOG_FILE}"
    MH_CORE_HC_FAIL_COUNT=$((MH_CORE_HC_FAIL_COUNT+1))
}

check_command() {
    local label="$1"
    shift

    # Health checks should collect as much evidence as possible. A failed check
    # is reported and counted instead of aborting the whole diagnostic run.
    if run "$@"; then
        health_ok "${label}"
    else
        health_fail "${label}"
    fi
}

check_service_active() {
    local service_name="$1"

    if systemctl is-active --quiet "${service_name}"; then
        health_ok "Service is running: ${service_name}"
    else
        health_fail "Service is not running: ${service_name}"
    fi
}

check_directory_mode_owner() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local interactive_fix="$5"

    if [[ ! -d "${path}" ]]; then
        health_fail "Missing directory: ${path}"
        return 0
    fi

    local actual_mode actual_owner actual_group
    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    if [[ "${actual_mode}" == "${expected_mode}" && "${actual_owner}" == "${expected_owner}" && "${actual_group}" == "${expected_group}" ]]; then
        health_ok "${path} has expected owner and mode."
    else
        health_fail "${path} is ${actual_owner}:${actual_group} ${actual_mode}; expected ${expected_owner}:${expected_group} ${expected_mode}."

        if [[ "${interactive_fix}" == "yes" ]]; then
            echo "For security, this directory should match the toolkit's expected ownership and mode."
            if confirm "Set ${path} to ${expected_owner}:${expected_group} ${expected_mode} now?"; then
                chown "${expected_owner}:${expected_group}" "${path}" || health_fail "Could not chown ${path}."
                chmod "${expected_mode}" "${path}" || health_fail "Could not chmod ${path}."
                health_ok "Fixed ${path}."
            fi
        fi
    fi
}

check_disk_space() {
    local path="$1"
    local warn_threshold_percent="85"
    local used

    if [[ ! -e "${path}" ]]; then
        health_warn "Cannot check disk usage because path does not exist: ${path}"
        return 0
    fi

    used="$(df -P "${path}" | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"
    if [[ -z "${used}" ]]; then
        health_warn "Could not determine disk usage for ${path}."
    elif (( used >= warn_threshold_percent )); then
        health_warn "Disk usage for ${path} is ${used}%."
    else
        health_ok "Disk usage for ${path} is ${used}%."
    fi
}

main_core_health_check() {
    local interactive_fix="no"
    local php_version

    if [[ "${1:-}" == "--interactive-fix" ]]; then
        interactive_fix="yes"
    fi

    echo
    info "Running core system health check."
    if [[ "${interactive_fix}" == "yes" ]]; then
        info "Interactive fixes are enabled for low-risk filesystem issues."
    else
        info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
    fi
    echo

    check_command "SSH configuration validates." validate_sshd_config
    check_command "Apache configuration validates." validate_apache_config

    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q '^Status: active'; then
            health_ok "UFW is active."
        else
            health_fail "UFW is installed but not active."
        fi
    else
        health_fail "UFW is not installed."
    fi

    check_service_active ssh
    check_service_active apache2
    check_service_active mariadb
    check_service_active redis-server

    for php_version in "${PHP_VERSIONS[@]}"; do
        if require_php_fpm_version "${php_version}"; then
            check_command "PHP-FPM ${php_version} configuration validates." validate_php_fpm_config "${php_version}"
            check_service_active "php${php_version}-fpm"
        else
            health_warn "PHP-FPM ${php_version} is configured in config.sh but not installed."
        fi
    done

    check_directory_mode_owner "${SERVER_ADMIN_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"
    check_directory_mode_owner "${SERVER_ADMIN_LOG_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"
    check_directory_mode_owner "${SERVER_ADMIN_BACKUP_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"
    check_directory_mode_owner "${SERVER_ADMIN_SSL_DIR}" 700 root root "${interactive_fix}"
    check_directory_mode_owner "${SERVER_ADMIN_STATE_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"

    if [[ -f "${BASE_SYSTEM_COMPLETE_FILE}" ]]; then
        health_ok "Base-system completion marker exists."
    else
        health_fail "Base-system completion marker is missing: ${BASE_SYSTEM_COMPLETE_FILE}"
    fi

    if [[ -f "$(sshd_managed_config_path)" ]]; then
        health_ok "Managed SSH fragment exists: $(sshd_managed_config_path)"
    else
        health_warn "Managed SSH fragment does not exist yet: $(sshd_managed_config_path)"
    fi

    check_disk_space "/"
    check_disk_space "${SERVER_ADMIN_DIR}"

    echo
    info "Core health check complete: ${MH_CORE_HC_PASS_COUNT} ok, ${MH_CORE_HC_WARN_COUNT} warnings, ${MH_CORE_HC_FAIL_COUNT} failures."

    if (( MH_CORE_HC_FAIL_COUNT > 0 )); then
        exit 1
    fi
}

main_core_health_check "$@"
