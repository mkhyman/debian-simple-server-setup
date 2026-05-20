#!/usr/bin/env bash
###############################################################################
# COMMON FUNCTIONS
#
# Helpers should be small and predictable. Scripts own control flow; common.sh
# provides reusable prompts, checks, file writers and state helpers.
###############################################################################

set -euo pipefail

_common_source="${BASH_SOURCE[0]}"
_common_dir="$(cd "$(dirname "${_common_source}")" && pwd)"

# Caller is normally either run_server_setup.sh in repo root or a script under
# scripts/. Work out the repo root without assuming an absolute clone path.
_caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
_caller_dir="$(cd "$(dirname "${_caller}")" && pwd)"

if [[ -f "${_caller_dir}/config.sh" ]]; then
    REPO_ROOT="${_caller_dir}"
elif [[ -f "${_caller_dir}/../config.sh" ]]; then
    REPO_ROOT="$(cd "${_caller_dir}/.." && pwd)"
elif [[ -f "${_common_dir}/../config.sh" ]]; then
    REPO_ROOT="$(cd "${_common_dir}/.." && pwd)"
else
    cat >&2 <<'EOF'
[ERROR] config.sh not found.

Create it from the example:

  cp config.example.sh config.sh
  nano config.sh
EOF
    exit 1
fi

source "${REPO_ROOT}/config.sh"

VERBOSE="no"
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE="yes"
fi

SCRIPT_NAME="$(basename "${_caller}" .sh)"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"

mkdir -p "${SERVER_ADMIN_LOG_DIR}"
LOG_FILE="${SERVER_ADMIN_LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
touch "${LOG_FILE}"
chmod 660 "${LOG_FILE}" 2>/dev/null || true

info() {
    echo "[INFO] $*"
    echo "[INFO] $*" >>"${LOG_FILE}"
}

warn() {
    echo "[WARN] $*"
    echo "[WARN] $*" >>"${LOG_FILE}"
}

ok() {
    echo "[OK] $*"
    echo "[OK] $*" >>"${LOG_FILE}"
}

fail() {
    echo "[ERROR] $*" >&2
    echo "[ERROR] $*" >>"${LOG_FILE}"
    echo
    echo "[ERROR] Full log: ${LOG_FILE}" >&2
    echo "[ERROR] Last 40 log lines:" >&2
    tail -n 40 "${LOG_FILE}" >&2 || true
    exit 1
}

confirm() {
    local prompt="$1"

    if [[ "${INTERACTIVE_CONFIRMATIONS}" != "yes" ]]; then
        return 0
    fi

    read -rp "${prompt} [y/N]: " answer
    [[ "${answer}" =~ ^[Yy]$ ]]
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        cat >&2 <<EOF
[ERROR] This script must be run as root or via sudo.

Example:
  sudo ./${SCRIPT_NAME}.sh
EOF
        exit 1
    fi
}

run() {
    info "Running: $*"

    if [[ "${VERBOSE}" == "yes" ]]; then
        "$@" 2>&1 | tee -a "${LOG_FILE}"
        local rc=${PIPESTATUS[0]}
        [[ "${rc}" -eq 0 ]] || return "${rc}"
    else
        "$@" >>"${LOG_FILE}" 2>&1 || return "$?"
    fi
}

backup_file() {
    local file="$1"

    [[ -f "${file}" ]] || return 0

    mkdir -p "${SERVER_ADMIN_BACKUP_DIR}"
    local safe_name backup_path
    safe_name="$(echo "${file}" | sed 's|^/||; s|/|-|g')_${TIMESTAMP}.bak"
    backup_path="${SERVER_ADMIN_BACKUP_DIR}/${safe_name}"

    cp -a "${file}" "${backup_path}" || return 1
    info "Backed up ${file} to ${backup_path}"
}

write_managed_file() {
    local file="$1"
    local mode="$2"
    local owner_group="$3"
    local temp_file="$4"

    if [[ -f "${file}" ]] && cmp -s "${file}" "${temp_file}"; then
        info "No change needed: ${file}"
        return 0
    fi

    if [[ -f "${file}" ]]; then
        warn "Managed file differs and may be overwritten: ${file}"
        if ! confirm "Overwrite ${file}?"; then
            info "Skipped overwrite: ${file}"
            return 1
        fi
        backup_file "${file}" || return 1
    fi

    mkdir -p "$(dirname "${file}")" || return 1
    cp "${temp_file}" "${file}" || return 1
    chown "${owner_group}" "${file}" || return 1
    chmod "${mode}" "${file}" || return 1
    ok "Wrote managed file: ${file}"
}

base_system_complete() {
    [[ -f "${BASE_SYSTEM_COMPLETE_FILE}" ]]
}

write_base_system_complete_marker() {
    mkdir -p "${SERVER_ADMIN_STATE_DIR}" || return 1

    {
        echo "completed_at=$(date -Is)"
        echo "script=core_base_system.sh"
        echo "toolkit_version=${SERVER_SETUP_TOOLKIT_VERSION}"
    } > "${BASE_SYSTEM_COMPLETE_FILE}" || return 1

    chown root:"${SERVER_ADMIN_GROUP}" "${BASE_SYSTEM_COMPLETE_FILE}" || return 1
    chmod 660 "${BASE_SYSTEM_COMPLETE_FILE}" || return 1
}

require_base_system_complete() {
    if ! base_system_complete; then
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

validate_linux_username() {
    local username="$1"
    [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

linux_user_exists() {
    local username="$1"
    id "${username}" >/dev/null 2>&1
}

ensure_linux_user() {
    local username="$1"

    if linux_user_exists "${username}"; then
        info "User already exists: ${username}"
        return 0
    fi

    run useradd -m -s /bin/bash "${username}"
}

ensure_user_in_group() {
    local username="$1"
    local group_name="$2"

    getent group "${group_name}" >/dev/null 2>&1 || return 1

    if id -nG "${username}" | tr ' ' '\n' | grep -qx "${group_name}"; then
        info "User ${username} is already in group ${group_name}."
        return 0
    fi

    run usermod -aG "${group_name}" "${username}"
}

ensure_user_in_sudo() {
    local username="$1"
    ensure_user_in_group "${username}" "sudo"
}

ensure_ssh_authorized_keys_file() {
    local username="$1"
    local home_dir ssh_dir auth_keys

    home_dir="$(getent passwd "${username}" | cut -d: -f6)"
    [[ -n "${home_dir}" ]] || return 1

    ssh_dir="${home_dir}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"

    install -d -m 700 -o "${username}" -g "${username}" "${ssh_dir}" || return 1
    touch "${auth_keys}" || return 1
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}

authorized_keys_file_for_user() {
    local username="$1"
    local home_dir

    home_dir="$(getent passwd "${username}" | cut -d: -f6)"
    [[ -n "${home_dir}" ]] || return 1

    echo "${home_dir}/.ssh/authorized_keys"
}

add_ssh_public_key() {
    local username="$1"
    local public_key="$2"
    local auth_keys

    ensure_ssh_authorized_keys_file "${username}" || return 1
    auth_keys="$(authorized_keys_file_for_user "${username}")" || return 1

    if grep -qxF "${public_key}" "${auth_keys}"; then
        info "SSH key already present for ${username}."
        return 0
    fi

    echo "${public_key}" >> "${auth_keys}" || return 1
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}

replace_ssh_public_keys() {
    local username="$1"
    local public_key="$2"
    local auth_keys

    ensure_ssh_authorized_keys_file "${username}" || return 1
    auth_keys="$(authorized_keys_file_for_user "${username}")" || return 1

    backup_file "${auth_keys}" || return 1
    printf '%s\n' "${public_key}" > "${auth_keys}" || return 1
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}

show_authorized_keys() {
    local username="$1"
    local auth_keys

    ensure_ssh_authorized_keys_file "${username}" || return 1
    auth_keys="$(authorized_keys_file_for_user "${username}")" || return 1

    if [[ ! -s "${auth_keys}" ]]; then
        echo "No SSH keys found for ${username}."
        return 0
    fi

    nl -ba "${auth_keys}"
}

remove_authorized_key_by_number() {
    local username="$1"
    local key_number="$2"
    local auth_keys tmp

    ensure_ssh_authorized_keys_file "${username}" || return 1
    auth_keys="$(authorized_keys_file_for_user "${username}")" || return 1

    [[ "${key_number}" =~ ^[0-9]+$ ]] || return 1
    sed -n "${key_number}p" "${auth_keys}" | grep -q . || return 1

    backup_file "${auth_keys}" || return 1
    tmp="$(mktemp)"
    awk -v n="${key_number}" 'NR != n { print }' "${auth_keys}" > "${tmp}" || return 1
    cat "${tmp}" > "${auth_keys}" || return 1
    rm -f "${tmp}"
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}

ensure_sshd_allow_user() {
    local username="$1"
    local sshd_config="/etc/ssh/sshd_config"

    backup_file "${sshd_config}" || return 1

    if grep -Eq "^[[:space:]]*AllowUsers[[:space:]]+" "${sshd_config}"; then
        local existing
        existing="$(grep -E "^[[:space:]]*AllowUsers[[:space:]]+" "${sshd_config}" | tail -n1 | sed -E 's/^[[:space:]]*AllowUsers[[:space:]]+//')"

        if echo " ${existing} " | grep -q " ${username} "; then
            info "AllowUsers already includes ${username}."
            return 0
        fi

        sed -i -E "s|^[[:space:]]*AllowUsers[[:space:]]+.*|AllowUsers ${existing} ${username}|" "${sshd_config}" || return 1
    else
        echo "AllowUsers ${username}" >> "${sshd_config}" || return 1
    fi

    /usr/sbin/sshd -t || return 1
    systemctl reload ssh || return 1
}

validate_hostname() {
    local host="$1"
    [[ "${host}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "${host}" == *.* ]]
}

hostname_to_username() {
    local host="$1"
    echo "${host}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]/_/g; s/_+/_/g; s/^_//; s/_$//'
}

site_home_for_user() {
    local site_user="$1"
    echo "${SITE_BASE_DIR}/${site_user}"
}

site_root_for_user() {
    local site_user="$1"
    echo "$(site_home_for_user "${site_user}")/${SITE_DOC_DIR}"
}

site_docroot_for_user() {
    local site_user="$1"
    local is_laravel="$2"

    if [[ "${is_laravel}" =~ ^[Yy]$ ]]; then
        echo "$(site_root_for_user "${site_user}")/public"
    else
        echo "$(site_root_for_user "${site_user}")"
    fi
}

ensure_website_directories() {
    local site_user="$1"
    local is_laravel="$2"
    local home root docroot

    linux_user_exists "${site_user}" || return 1

    home="$(site_home_for_user "${site_user}")"
    root="$(site_root_for_user "${site_user}")"
    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"

    install -d -m 750 -o "${site_user}" -g "${site_user}" "${home}" || return 1
    install -d -m 750 -o "${site_user}" -g "${site_user}" "${root}" || return 1
    install -d -m 750 -o "${site_user}" -g "${site_user}" "${home}/${SITE_LOG_DIR}" || return 1
    install -d -m 750 -o "${site_user}" -g "${site_user}" "${home}/${SITE_TMP_DIR}" || return 1
    install -d -m 750 -o "${site_user}" -g "${site_user}" "${docroot}" || return 1

    if [[ "${is_laravel}" =~ ^[Yy]$ ]]; then
        install -d -m 775 -o "${site_user}" -g "${site_user}" "${root}/storage" || return 1
        install -d -m 775 -o "${site_user}" -g "${site_user}" "${root}/bootstrap/cache" || return 1
    fi
}

ensure_website_acls() {
    local site_user="$1"
    local is_laravel="$2"
    local home root docroot logs tmpdir

    home="$(site_home_for_user "${site_user}")"
    root="$(site_root_for_user "${site_user}")"
    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"
    logs="${home}/${SITE_LOG_DIR}"
    tmpdir="${home}/${SITE_TMP_DIR}"

    command -v setfacl >/dev/null 2>&1 || return 1

    setfacl -m "u:${APACHE_RUN_USER}:--x" "${home}" || return 1
    setfacl -m "u:${APACHE_RUN_USER}:--x" "${root}" || return 1
    setfacl -m "u:${APACHE_RUN_USER}:rx" "${docroot}" || return 1
    setfacl -m "u:${APACHE_RUN_USER}:rwx" "${logs}" || return 1
    setfacl -m "u:${APACHE_RUN_USER}:rwx" "${tmpdir}" || return 1
}

# Returns:
#   0 = user and expected directories are ready
#   1 = Linux user missing
#   2 = site root missing
#   3 = document root missing
is_site_user_ready() {
    local site_user="$1"
    local is_laravel="$2"
    local root docroot

    linux_user_exists "${site_user}" || return 1

    root="$(site_root_for_user "${site_user}")"
    [[ -d "${root}" ]] || return 2

    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"
    [[ -d "${docroot}" ]] || return 3
}

require_php_fpm_version() {
    local php_version="$1"
    [[ -d "/etc/php/${php_version}/fpm" ]]
}

certificate_dir_for_name() {
    local cert_name="$1"
    echo "${SERVER_ADMIN_SSL_DIR}/${cert_name}"
}

require_certificate_files() {
    local cert_name="$1"
    local cert_dir

    cert_dir="$(certificate_dir_for_name "${cert_name}")"
    [[ -f "${cert_dir}/fullchain.pem" ]] || return 1
    [[ -f "${cert_dir}/privkey.pem" ]] || return 1
}

check_cert_covers_hostname() {
    local cert_file="$1"
    local hostname="$2"
    local base text

    base="${hostname#*.}"
    text="$(openssl x509 -in "${cert_file}" -noout -text)"

    if echo "${text}" | grep -Eq "DNS:${hostname}([,[:space:]]|$)"; then
        return 0
    fi

    if [[ "${hostname}" == *.* ]] && echo "${text}" | grep -Eq "DNS:\\*\\.${base}([,[:space:]]|$)"; then
        return 0
    fi

    return 1
}

managed_header() {
    local generated_by="$1"

    cat <<EOF
###############################################################################
# MANAGED FILE
#
# Server Setup Toolkit Version: ${SERVER_SETUP_TOOLKIT_VERSION}
# Generated by: ${generated_by}
# Generated at: $(date -Is)
#
# Manual edits may be overwritten by rerunning the setup scripts.
###############################################################################
EOF
}
