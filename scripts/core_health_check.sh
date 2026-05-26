#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

MH_CORE_HC_PASS_COUNT=0
MH_CORE_HC_WARN_COUNT=0
MH_CORE_HC_FAIL_COUNT=0

core_health_ok() {
    log_ok "$*"
    MH_CORE_HC_PASS_COUNT=$((MH_CORE_HC_PASS_COUNT+1))
}

core_health_warn() {
    log_warn "$*"
    MH_CORE_HC_WARN_COUNT=$((MH_CORE_HC_WARN_COUNT+1))
}

core_health_fail() {
    echo "[FAIL] $*"
    echo "[FAIL] $*" >>"${LOG_FILE}"
    MH_CORE_HC_FAIL_COUNT=$((MH_CORE_HC_FAIL_COUNT+1))
}

core_hc_command_succeeds() {
    "$@" >/dev/null 2>&1
}

core_hc_directory_matches_owner_mode() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"

    [[ -d "${path}" ]] || return 1
    [[ "$(stat -c '%U:%G %a' "${path}")" == "${expected_owner}:${expected_group} ${expected_mode}" ]]
}

core_hc_disk_usage_percent() {
    local path="$1"
    [[ -e "${path}" ]] || return 1
    df -P "${path}" | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}

core_hc_fix_directory_owner_mode() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"

    [[ -d "${path}" ]] || return 1
    chown "${expected_owner}:${expected_group}" "${path}" || return 1

    # Directory special bits can survive numeric chmod in some cases. Clear
    # them before applying the expected mode so interactive repairs do not leave
    # confusing modes such as 2700 when 700 was requested.
    chmod u-s,g-s,-t "${path}" || return 1
    chmod "${expected_mode}" "${path}"
}

core_hc_report_command() {
    local ok_message="$1"
    local fail_message="$2"
    shift 2

    log_info "Running: $*"
    if core_hc_command_succeeds "$@"; then
        core_health_ok "${ok_message}"
    else
        core_health_fail "${fail_message}"
    fi
}

core_hc_report_service_active() {
    local service_name="$1"

    if svc_is_active "${service_name}"; then
        core_health_ok "Service is running: ${service_name}"
    else
        core_health_fail "Service is not running: ${service_name}"
    fi
}

core_hc_report_directory_owner_mode() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local interactive_fix="$5"

    if [[ ! -d "${path}" ]]; then
        core_health_fail "Missing directory: ${path}"
        return 0
    fi

    if core_hc_directory_matches_owner_mode "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}"; then
        core_health_ok "${path} has expected owner and mode."
        return 0
    fi

    local actual_mode actual_owner actual_group
    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    core_health_fail "${path} is ${actual_owner}:${actual_group} ${actual_mode}; expected ${expected_owner}:${expected_group} ${expected_mode}."

    if [[ "${interactive_fix}" == "yes" ]]; then
        echo "For security, this directory should match the toolkit's expected ownership and mode."
        if prompt_confirm "Set ${path} to ${expected_owner}:${expected_group} ${expected_mode} now?"; then
            if core_hc_fix_directory_owner_mode "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}"; then
                core_health_ok "Fixed ${path}."
            else
                core_health_fail "Could not fix ${path}."
            fi
        fi
    fi
}

core_hc_report_disk_space() {
    local path="$1"
    local warn_threshold_percent="85"
    local used

    if ! used="$(core_hc_disk_usage_percent "${path}")"; then
        core_health_warn "Cannot check disk usage because path does not exist: ${path}"
        return 0
    fi

    if [[ -z "${used}" ]]; then
        core_health_warn "Could not determine disk usage for ${path}."
    elif (( used >= warn_threshold_percent )); then
        core_health_warn "Disk usage for ${path} is ${used}%."
    else
        core_health_ok "Disk usage for ${path} is ${used}%."
    fi
}

core_hc_offer_toolkit_permission_repair() {
    if ! prompt_confirm "Reapply toolkit file permissions under ${SERVER_ADMIN_DIR}?"; then
        return 0
    fi

    log_info "Setting shared toolkit root permissions."
    file_set_server_admin_root_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
        || { core_health_fail "Could not set ${SERVER_ADMIN_DIR} to root:${SERVER_ADMIN_GROUP} 2770."; return 1; }

    log_info "Setting shared toolkit directory permissions."
    file_set_server_admin_directory_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
        || { core_health_fail "Could not set server-admin directory permissions."; return 1; }

    log_info "Making toolkit shell scripts executable by server-admin users."
    file_set_server_admin_script_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
        || { core_health_fail "Could not set server-admin script permissions."; return 1; }

    log_info "Making toolkit non-script files group-maintainable."
    file_set_server_admin_regular_file_permissions "${SERVER_ADMIN_DIR}" "${SERVER_ADMIN_GROUP}" \
        || { core_health_fail "Could not set server-admin file permissions."; return 1; }

    log_info "Restricting SSL certificate storage to root only."
    file_harden_server_admin_ssl_directory "${SERVER_ADMIN_SSL_DIR}" \
        || { core_health_fail "Could not harden SSL certificate storage: ${SERVER_ADMIN_SSL_DIR}."; return 1; }

    core_health_ok "Reapplied toolkit file permissions."
}

main_core_health_check() {
    local interactive_fix="no"
    local php_version

    if [[ "${1:-}" == "--interactive-fix" ]]; then
        interactive_fix="yes"
    fi

    echo
    log_info "Running core system health check."
    if [[ "${interactive_fix}" == "yes" ]]; then
        log_info "Interactive fixes are enabled for low-risk filesystem issues."
    else
        log_info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
    fi
    echo

    if user_system_group_exists "${SERVER_ADMIN_GROUP}"; then
        core_health_ok "Server admin group exists: ${SERVER_ADMIN_GROUP}"
    else
        core_health_fail "Server admin group is missing: ${SERVER_ADMIN_GROUP}"
        if [[ "${interactive_fix}" == "yes" ]] && prompt_confirm "Create server admin group ${SERVER_ADMIN_GROUP} now?"; then
            if user_create_system_group "${SERVER_ADMIN_GROUP}"; then
                core_health_ok "Created server admin group: ${SERVER_ADMIN_GROUP}"
            else
                core_health_fail "Could not create server admin group: ${SERVER_ADMIN_GROUP}"
            fi
        fi
    fi

    core_hc_report_command "SSH configuration validates." "SSH configuration does not validate." ssh_validate_daemon_config
    core_hc_report_command "Apache configuration validates." "Apache configuration does not validate." apache_validate_config

    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q '^Status: active'; then
            core_health_ok "UFW is active."
        else
            core_health_fail "UFW is installed but not active."
        fi
    else
        core_health_fail "UFW is not installed."
    fi

    core_hc_report_service_active ssh
    core_hc_report_service_active apache2
    core_hc_report_service_active mariadb
    core_hc_report_service_active redis-server

    for php_version in "${PHP_VERSIONS[@]}"; do
        if fpm_version_exists "${php_version}"; then
            core_hc_report_command "PHP-FPM ${php_version} configuration validates." "PHP-FPM ${php_version} configuration does not validate." fpm_validate_config "${php_version}"
            core_hc_report_service_active "php${php_version}-fpm"
        else
            core_health_warn "PHP-FPM ${php_version} is configured in config.sh but not installed."
        fi
    done

    core_hc_report_directory_owner_mode "${SERVER_ADMIN_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"
    core_hc_report_directory_owner_mode "${SERVER_ADMIN_LOG_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"
    core_hc_report_directory_owner_mode "${SERVER_ADMIN_BACKUP_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"
    core_hc_report_directory_owner_mode "${SERVER_ADMIN_SSL_DIR}" 700 root root "${interactive_fix}"
    core_hc_report_directory_owner_mode "${SERVER_ADMIN_STATE_DIR}" 2770 root "${SERVER_ADMIN_GROUP}" "${interactive_fix}"

    if [[ "${interactive_fix}" == "yes" ]]; then
        core_hc_offer_toolkit_permission_repair
    fi

    if [[ -f "${BASE_SYSTEM_COMPLETE_FILE}" ]]; then
        core_health_ok "Base-system completion marker exists."
    else
        core_health_fail "Base-system completion marker is missing: ${BASE_SYSTEM_COMPLETE_FILE}"
    fi

    if [[ -f "$(ssh_daemon_managed_config_path)" ]]; then
        core_health_ok "Managed SSH fragment exists: $(ssh_daemon_managed_config_path)"
    else
        core_health_warn "Managed SSH fragment does not exist yet: $(ssh_daemon_managed_config_path)"
    fi

    core_hc_report_disk_space "/"
    core_hc_report_disk_space "${SERVER_ADMIN_DIR}"

    echo
    log_info "Core health check complete: ${MH_CORE_HC_PASS_COUNT} passed, ${MH_CORE_HC_WARN_COUNT} warnings, ${MH_CORE_HC_FAIL_COUNT} failures."

    if (( MH_CORE_HC_FAIL_COUNT > 0 )); then
        exit 1
    fi
}

main_core_health_check "$@"
