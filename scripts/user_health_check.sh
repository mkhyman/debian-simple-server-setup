#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

MH_USER_HC_PASS_COUNT=0
MH_USER_HC_WARN_COUNT=0
MH_USER_HC_FAIL_COUNT=0

user_health_ok() { log_ok "$*"; MH_USER_HC_PASS_COUNT=$((MH_USER_HC_PASS_COUNT+1)); }
user_health_warn() { log_warn "$*"; MH_USER_HC_WARN_COUNT=$((MH_USER_HC_WARN_COUNT+1)); }
user_health_fail() { echo "[FAIL] $*"; echo "[FAIL] $*" >>"${LOG_FILE}"; MH_USER_HC_FAIL_COUNT=$((MH_USER_HC_FAIL_COUNT+1)); }

user_hc_path_matches_owner_mode() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"

    [[ -e "${path}" ]] || return 1
    [[ "$(stat -c '%U:%G %a' "${path}")" == "${expected_owner}:${expected_group} ${expected_mode}" ]]
}

user_hc_fix_directory_owner_mode() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"

    install -d -m "${mode}" -o "${owner}" -g "${group}" "${path}"
}

user_hc_fix_file_owner_mode() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"

    touch "${path}" || return 1
    chown "${owner}:${group}" "${path}" || return 1
    chmod "${mode}" "${path}"
}

user_hc_offer_directory_fix() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "${reason}"
    if prompt_confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        if user_hc_fix_directory_owner_mode "${path}" "${mode}" "${owner}" "${group}"; then
            user_health_ok "Fixed ${path}."
        else
            user_health_fail "Could not fix ${path}."
        fi
    fi
}

user_hc_offer_file_fix() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "${reason}"
    if prompt_confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        if user_hc_fix_file_owner_mode "${path}" "${mode}" "${owner}" "${group}"; then
            user_health_ok "Fixed ${path}."
        else
            user_health_fail "Could not fix ${path}."
        fi
    fi
}

user_hc_report_path_owner_mode() {
    local path="$1"
    local type="$2"
    local expected_mode="$3"
    local expected_owner="$4"
    local expected_group="$5"
    local reason="$6"
    local interactive_fix="$7"

    if [[ "${type}" == "dir" && ! -d "${path}" ]]; then
        user_health_fail "Missing directory: ${path}"
        user_hc_offer_directory_fix "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        return 0
    fi

    if [[ "${type}" == "file" && ! -f "${path}" ]]; then
        user_health_warn "Missing file: ${path}"
        user_hc_offer_file_fix "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        return 0
    fi

    if user_hc_path_matches_owner_mode "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}"; then
        user_health_ok "${path} has expected owner and mode."
        return 0
    fi

    local actual_mode actual_owner actual_group
    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    user_health_fail "${path} is ${actual_owner}:${actual_group} ${actual_mode}; expected ${expected_owner}:${expected_group} ${expected_mode}."
    if [[ "${type}" == "dir" ]]; then
        user_hc_offer_directory_fix "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
    else
        user_hc_offer_file_fix "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
    fi
}

main_user_health_check() {
    local interactive_fix="no"
    local target_user=""
    local arg
    local home_dir shell_path home_owner ssh_dir auth_keys

    for arg in "$@"; do
        case "${arg}" in
            --interactive-fix) interactive_fix="yes" ;;
            *) target_user="${arg}" ;;
        esac
    done

    if [[ -z "${target_user}" ]]; then
        read -rp "Linux username to check: " target_user
    fi

    user_validate_system_username "${target_user}" || log_fail "Invalid Linux username: ${target_user}"

    echo
    log_info "Running user health check for ${target_user}."
    if [[ "${interactive_fix}" == "yes" ]]; then
        log_info "Interactive fixes are enabled for low-risk filesystem issues."
    else
        log_info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
    fi
    echo

    if ! user_system_user_exists "${target_user}"; then
        user_health_fail "Linux user does not exist: ${target_user}"
        log_info "User health check complete: ${MH_USER_HC_PASS_COUNT} passed, ${MH_USER_HC_WARN_COUNT} warnings, ${MH_USER_HC_FAIL_COUNT} failures."
        exit 1
    fi
    user_health_ok "Linux user exists: ${target_user}"

    home_dir="$(getent passwd "${target_user}" | cut -d: -f6)"
    shell_path="$(getent passwd "${target_user}" | cut -d: -f7)"

    if [[ -d "${home_dir}" ]]; then
        user_health_ok "Home directory exists: ${home_dir}"
    else
        user_health_fail "Home directory is missing: ${home_dir}"
    fi

    home_owner="$(stat -c '%U' "${home_dir}" 2>/dev/null || true)"
    if [[ "${home_owner}" == "${target_user}" ]]; then
        user_health_ok "Home directory is owned by ${target_user}."
    else
        user_health_fail "Home directory owner is ${home_owner:-unknown}; expected ${target_user}."
    fi

    case "${shell_path}" in
        /bin/bash|/usr/bin/bash|/bin/sh|/usr/bin/sh) user_health_ok "Login shell is conventional: ${shell_path}" ;;
        *) user_health_warn "Login shell is unusual: ${shell_path}" ;;
    esac

    ssh_dir="${home_dir}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"

    user_hc_report_path_owner_mode "${ssh_dir}" dir 700 "${target_user}" "${target_user}" ".ssh must not be accessible by other users; OpenSSH may reject loose permissions." "${interactive_fix}"
    user_hc_report_path_owner_mode "${auth_keys}" file 600 "${target_user}" "${target_user}" "authorized_keys should be readable only by the account owner." "${interactive_fix}"

    if [[ -f "${auth_keys}" && -s "${auth_keys}" ]]; then
        user_health_ok "authorized_keys contains at least one key."
    elif [[ -f "${auth_keys}" ]]; then
        user_health_warn "authorized_keys exists but is empty."
    fi

    echo
    log_info "User health check complete: ${MH_USER_HC_PASS_COUNT} passed, ${MH_USER_HC_WARN_COUNT} warnings, ${MH_USER_HC_FAIL_COUNT} failures."

    if (( MH_USER_HC_FAIL_COUNT > 0 )); then
        exit 1
    fi
}

main_user_health_check "$@"
