#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

MH_USER_HC_PASS_COUNT=0
MH_USER_HC_WARN_COUNT=0
MH_USER_HC_FAIL_COUNT=0

health_ok() { ok "$*"; MH_USER_HC_PASS_COUNT=$((MH_USER_HC_PASS_COUNT+1)); }
health_warn() { warn "$*"; MH_USER_HC_WARN_COUNT=$((MH_USER_HC_WARN_COUNT+1)); }
health_fail() { echo "[FAIL] $*"; echo "[FAIL] $*" >>"${LOG_FILE}"; MH_USER_HC_FAIL_COUNT=$((MH_USER_HC_FAIL_COUNT+1)); }

user_hc_path_exists() {
    local path="$1"
    local type="$2"

    case "${type}" in
        dir) [[ -d "${path}" ]] ;;
        file) [[ -f "${path}" ]] ;;
        *) return 1 ;;
    esac
}

user_hc_path_has_mode_owner() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local actual_mode actual_owner actual_group

    [[ -e "${path}" ]] || return 1

    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    [[ "${actual_mode}" == "${expected_mode}" \
        && "${actual_owner}" == "${expected_owner}" \
        && "${actual_group}" == "${expected_group}" ]]
}

user_hc_describe_path_mode_owner() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local actual_mode actual_owner actual_group

    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    echo "${path} is ${actual_owner}:${actual_group} ${actual_mode}; expected ${expected_owner}:${expected_group} ${expected_mode}."
}

user_hc_offer_fix_dir() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "${reason}"
    if confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        install -d -m "${mode}" -o "${owner}" -g "${group}" "${path}" || { health_fail "Could not fix ${path}."; return 1; }
        health_ok "Fixed ${path}."
    fi
}

user_hc_offer_fix_file() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "${reason}"
    if confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        touch "${path}" || { health_fail "Could not create ${path}."; return 1; }
        chown "${owner}:${group}" "${path}" || { health_fail "Could not chown ${path}."; return 1; }
        chmod "${mode}" "${path}" || { health_fail "Could not chmod ${path}."; return 1; }
        health_ok "Fixed ${path}."
    fi
}

user_hc_report_path_mode_owner() {
    local path="$1"
    local type="$2"
    local expected_mode="$3"
    local expected_owner="$4"
    local expected_group="$5"
    local reason="$6"
    local interactive_fix="$7"

    if ! user_hc_path_exists "${path}" "${type}"; then
        if [[ "${type}" == "dir" ]]; then
            health_fail "Missing directory: ${path}"
            user_hc_offer_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        else
            health_warn "Missing file: ${path}"
            user_hc_offer_fix_file "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        fi
        return 0
    fi

    if user_hc_path_has_mode_owner "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}"; then
        health_ok "${path} has expected owner and mode."
    else
        health_fail "$(user_hc_describe_path_mode_owner "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}")"
        if [[ "${type}" == "dir" ]]; then
            user_hc_offer_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        else
            user_hc_offer_fix_file "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        fi
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

    validate_linux_username "${target_user}" || fail "Invalid Linux username: ${target_user}"

    echo
    info "Running user health check for ${target_user}."
    if [[ "${interactive_fix}" == "yes" ]]; then
        info "Interactive fixes are enabled for low-risk filesystem issues."
    else
        info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
    fi
    echo

    if ! linux_user_exists "${target_user}"; then
        health_fail "Linux user does not exist: ${target_user}"
        info "User health check complete: ${MH_USER_HC_PASS_COUNT} ok, ${MH_USER_HC_WARN_COUNT} warnings, ${MH_USER_HC_FAIL_COUNT} failures."
        exit 1
    fi
    health_ok "Linux user exists: ${target_user}"

    home_dir="$(getent passwd "${target_user}" | cut -d: -f6)"
    shell_path="$(getent passwd "${target_user}" | cut -d: -f7)"

    if [[ -d "${home_dir}" ]]; then
        health_ok "Home directory exists: ${home_dir}"
    else
        health_fail "Home directory is missing: ${home_dir}"
    fi

    home_owner="$(stat -c '%U' "${home_dir}" 2>/dev/null || true)"
    if [[ "${home_owner}" == "${target_user}" ]]; then
        health_ok "Home directory is owned by ${target_user}."
    else
        health_fail "Home directory owner is ${home_owner:-unknown}; expected ${target_user}."
    fi

    case "${shell_path}" in
        /bin/bash|/usr/bin/bash|/bin/sh|/usr/bin/sh) health_ok "Login shell is conventional: ${shell_path}" ;;
        *) health_warn "Login shell is unusual: ${shell_path}" ;;
    esac

    ssh_dir="${home_dir}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"

    user_hc_report_path_mode_owner "${ssh_dir}" dir 700 "${target_user}" "${target_user}" ".ssh must not be accessible by other users; OpenSSH may reject loose permissions." "${interactive_fix}"
    user_hc_report_path_mode_owner "${auth_keys}" file 600 "${target_user}" "${target_user}" "authorized_keys should be readable only by the account owner." "${interactive_fix}"

    if [[ -f "${auth_keys}" && -s "${auth_keys}" ]]; then
        health_ok "authorized_keys contains at least one key."
    elif [[ -f "${auth_keys}" ]]; then
        health_warn "authorized_keys exists but is empty."
    fi

    echo
    info "User health check complete: ${MH_USER_HC_PASS_COUNT} ok, ${MH_USER_HC_WARN_COUNT} warnings, ${MH_USER_HC_FAIL_COUNT} failures."

    if (( MH_USER_HC_FAIL_COUNT > 0 )); then
        exit 1
    fi
}

main_user_health_check "$@"
