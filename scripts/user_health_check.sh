#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

INTERACTIVE_FIX="no"
TARGET_USER=""

for arg in "$@"; do
    case "${arg}" in
        --interactive-fix) INTERACTIVE_FIX="yes" ;;
        *) TARGET_USER="${arg}" ;;
    esac
done

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

health_ok() { ok "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
health_warn() { warn "$*"; WARN_COUNT=$((WARN_COUNT+1)); }
health_fail() { echo "[FAIL] $*"; echo "[FAIL] $*" >>"${LOG_FILE}"; FAIL_COUNT=$((FAIL_COUNT+1)); }

maybe_fix_dir() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"

    [[ "${INTERACTIVE_FIX}" == "yes" ]] || return 0
    echo "${reason}"
    if confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        install -d -m "${mode}" -o "${owner}" -g "${group}" "${path}" || { health_fail "Could not fix ${path}."; return 1; }
        health_ok "Fixed ${path}."
    fi
}

maybe_fix_file() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"

    [[ "${INTERACTIVE_FIX}" == "yes" ]] || return 0
    echo "${reason}"
    if confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        touch "${path}" || { health_fail "Could not create ${path}."; return 1; }
        chown "${owner}:${group}" "${path}" || { health_fail "Could not chown ${path}."; return 1; }
        chmod "${mode}" "${path}" || { health_fail "Could not chmod ${path}."; return 1; }
        health_ok "Fixed ${path}."
    fi
}

check_path() {
    local path="$1"
    local type="$2"
    local expected_mode="$3"
    local expected_owner="$4"
    local expected_group="$5"
    local reason="$6"

    if [[ "${type}" == "dir" && ! -d "${path}" ]]; then
        health_fail "Missing directory: ${path}"
        maybe_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}"
        return 0
    fi

    if [[ "${type}" == "file" && ! -f "${path}" ]]; then
        health_warn "Missing file: ${path}"
        maybe_fix_file "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}"
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
        if [[ "${type}" == "dir" ]]; then
            maybe_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}"
        else
            maybe_fix_file "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}"
        fi
    fi
}

if [[ -z "${TARGET_USER}" ]]; then
    read -rp "Linux username to check: " TARGET_USER
fi

validate_linux_username "${TARGET_USER}" || fail "Invalid Linux username: ${TARGET_USER}"

echo
info "Running user health check for ${TARGET_USER}."
if [[ "${INTERACTIVE_FIX}" == "yes" ]]; then
    info "Interactive fixes are enabled for low-risk filesystem issues."
else
    info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
fi
echo

if ! linux_user_exists "${TARGET_USER}"; then
    health_fail "Linux user does not exist: ${TARGET_USER}"
    info "User health check complete: ${PASS_COUNT} ok, ${WARN_COUNT} warnings, ${FAIL_COUNT} failures."
    exit 1
fi
health_ok "Linux user exists: ${TARGET_USER}"

home_dir="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
shell_path="$(getent passwd "${TARGET_USER}" | cut -d: -f7)"

if [[ -d "${home_dir}" ]]; then
    health_ok "Home directory exists: ${home_dir}"
else
    health_fail "Home directory is missing: ${home_dir}"
fi

home_owner="$(stat -c '%U' "${home_dir}" 2>/dev/null || true)"
if [[ "${home_owner}" == "${TARGET_USER}" ]]; then
    health_ok "Home directory is owned by ${TARGET_USER}."
else
    health_fail "Home directory owner is ${home_owner:-unknown}; expected ${TARGET_USER}."
fi

case "${shell_path}" in
    /bin/bash|/usr/bin/bash|/bin/sh|/usr/bin/sh) health_ok "Login shell is conventional: ${shell_path}" ;;
    *) health_warn "Login shell is unusual: ${shell_path}" ;;
esac

ssh_dir="${home_dir}/.ssh"
auth_keys="${ssh_dir}/authorized_keys"

check_path "${ssh_dir}" dir 700 "${TARGET_USER}" "${TARGET_USER}" ".ssh must not be accessible by other users; OpenSSH may reject loose permissions."
check_path "${auth_keys}" file 600 "${TARGET_USER}" "${TARGET_USER}" "authorized_keys should be readable only by the account owner."

if [[ -f "${auth_keys}" && -s "${auth_keys}" ]]; then
    health_ok "authorized_keys contains at least one key."
elif [[ -f "${auth_keys}" ]]; then
    health_warn "authorized_keys exists but is empty."
fi

echo
info "User health check complete: ${PASS_COUNT} ok, ${WARN_COUNT} warnings, ${FAIL_COUNT} failures."

if (( FAIL_COUNT > 0 )); then
    exit 1
fi
