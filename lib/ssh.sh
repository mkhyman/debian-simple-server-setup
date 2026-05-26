#!/usr/bin/env bash
###############################################################################
# SSH HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

ssh_ensure_authorized_keys_file() {
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


ssh_authorized_keys_file_for_user() {
    local username="$1"
    local home_dir

    home_dir="$(getent passwd "${username}" | cut -d: -f6)"
    [[ -n "${home_dir}" ]] || return 1

    echo "${home_dir}/.ssh/authorized_keys"
}


ssh_add_public_key() {
    local username="$1"
    local public_key="$2"
    local auth_keys

    ssh_ensure_authorized_keys_file "${username}" || return 1
    auth_keys="$(ssh_authorized_keys_file_for_user "${username}")" || return 1

    if grep -qxF "${public_key}" "${auth_keys}"; then
        log_info "SSH key already present for ${username}."
        return 0
    fi

    echo "${public_key}" >> "${auth_keys}" || return 1
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}


ssh_replace_public_keys() {
    local username="$1"
    local public_key="$2"
    local auth_keys

    ssh_ensure_authorized_keys_file "${username}" || return 1
    auth_keys="$(ssh_authorized_keys_file_for_user "${username}")" || return 1

    file_backup "${auth_keys}" || return 1
    printf '%s\n' "${public_key}" > "${auth_keys}" || return 1
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}


ssh_show_authorized_keys() {
    local username="$1"
    local auth_keys

    ssh_ensure_authorized_keys_file "${username}" || return 1
    auth_keys="$(ssh_authorized_keys_file_for_user "${username}")" || return 1

    if [[ ! -s "${auth_keys}" ]]; then
        echo "No SSH keys found for ${username}."
        return 0
    fi

    nl -ba "${auth_keys}"
}


ssh_remove_authorized_key_by_number() {
    local username="$1"
    local key_number="$2"
    local auth_keys tmp

    ssh_ensure_authorized_keys_file "${username}" || return 1
    auth_keys="$(ssh_authorized_keys_file_for_user "${username}")" || return 1

    [[ "${key_number}" =~ ^[0-9]+$ ]] || return 1
    sed -n "${key_number}p" "${auth_keys}" | grep -q . || return 1

    file_backup "${auth_keys}" || return 1
    tmp="$(mktemp)"
    awk -v n="${key_number}" 'NR != n { print }' "${auth_keys}" > "${tmp}" || return 1
    cat "${tmp}" > "${auth_keys}" || return 1
    rm -f "${tmp}"
    chown "${username}:${username}" "${auth_keys}" || return 1
    chmod 600 "${auth_keys}" || return 1
}


ssh_daemon_main_config_path() {
    echo "/etc/ssh/sshd_config"
}


ssh_daemon_config_dir_path() {
    echo "/etc/ssh/sshd_config.d"
}


ssh_daemon_managed_config_path() {
    echo "$(ssh_daemon_config_dir_path)/server-admin.conf"
}


ssh_daemon_main_config_has_fragment_include() {
    local sshd_config
    sshd_config="$(ssh_daemon_main_config_path)"

    grep -Eq "^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]+.*)?$" "${sshd_config}"
}


ssh_create_daemon_config_dir() {
    install -d -m 755 -o root -g root "$(ssh_daemon_config_dir_path)"
}


ssh_write_main_config_with_fragment_include() {
    local sshd_config="$1"
    local destination="$2"

    {
        echo "Include /etc/ssh/sshd_config.d/*.conf"
        echo
        cat "${sshd_config}"
    } > "${destination}"
}


ssh_install_main_config_candidate() {
    local candidate="$1"
    local sshd_config
    sshd_config="$(ssh_daemon_main_config_path)"

    cp "${candidate}" "${sshd_config}" || return 1
    chown root:root "${sshd_config}" || return 1
    chmod 644 "${sshd_config}"
}


ssh_restore_main_config_from_backup() {
    local backup="$1"
    local sshd_config
    sshd_config="$(ssh_daemon_main_config_path)"

    cp "${backup}" "${sshd_config}"
}


ssh_add_fragment_include_to_main_config() {
    local sshd_config tmp_original tmp_new
    sshd_config="$(ssh_daemon_main_config_path)"
    tmp_original="$(mktemp)"
    tmp_new="$(mktemp)"

    cp -a "${sshd_config}" "${tmp_original}" || { rm -f "${tmp_original}" "${tmp_new}"; return 1; }
    ssh_write_main_config_with_fragment_include "${sshd_config}" "${tmp_new}" || { rm -f "${tmp_original}" "${tmp_new}"; return 1; }
    ssh_install_main_config_candidate "${tmp_new}" || { ssh_restore_main_config_from_backup "${tmp_original}" || true; rm -f "${tmp_original}" "${tmp_new}"; return 1; }

    if ! ssh_validate_daemon_config >/dev/null 2>&1; then
        ssh_restore_main_config_from_backup "${tmp_original}" || true
        rm -f "${tmp_original}" "${tmp_new}"
        return 1
    fi

    rm -f "${tmp_original}" "${tmp_new}"
}


ssh_ensure_daemon_config_fragments_enabled() {
    ssh_create_daemon_config_dir || return 1
    ssh_daemon_main_config_has_fragment_include && return 0

    file_backup "$(ssh_daemon_main_config_path)" || return 1
    ssh_add_fragment_include_to_main_config
}


ssh_daemon_collect_allow_users() {
    local file

    for file in "$(ssh_daemon_managed_config_path)" "$(ssh_daemon_main_config_path)"; do
        [[ -f "${file}" ]] || continue
        grep -E "^[[:space:]]*AllowUsers[[:space:]]+" "${file}" \
            | sed -E 's/^[[:space:]]*AllowUsers[[:space:]]+//' \
            | tr ' ' '\n' \
            | awk 'NF'
    done | awk '!seen[$0]++'
}


ssh_daemon_managed_fragment_has_permit_root_disabled() {
    local managed_config
    managed_config="$(ssh_daemon_managed_config_path)"

    [[ -f "${managed_config}" ]] || return 1
    grep -Eq "^[[:space:]]*PermitRootLogin[[:space:]]+no([[:space:]]+.*)?$" "${managed_config}"
}


ssh_write_daemon_managed_fragment() {
    local permit_root_login_no="$1"
    shift || true

    local managed_config tmp user allow_users=()
    managed_config="$(ssh_daemon_managed_config_path)"
    tmp="$(mktemp)"

    for user in $(ssh_daemon_collect_allow_users) "$@"; do
        [[ -n "${user}" ]] || continue
        if ! printf '%s\n' "${allow_users[@]:-}" | grep -qxF "${user}"; then
            allow_users+=("${user}")
        fi
    done

    {
        echo "# Managed by server-admin."
        echo "#"
        echo "# This fragment keeps local SSH policy separate from Debian's packaged"
        echo "# sshd_config so upgrades and local recovery remain easy to reason about."
        echo
        if [[ "${permit_root_login_no}" == "yes" ]]; then
            echo "PermitRootLogin no"
        fi
        if [[ "${#allow_users[@]}" -gt 0 ]]; then
            echo "AllowUsers ${allow_users[*]}"
        fi
    } > "${tmp}" || { rm -f "${tmp}"; return 1; }

    ssh_ensure_daemon_config_fragments_enabled || { rm -f "${tmp}"; return 1; }
    file_write_managed "${managed_config}" 0644 root:root "${tmp}" || { rm -f "${tmp}"; return 1; }
    rm -f "${tmp}"
}


ssh_ensure_daemon_allow_user() {
    local username="$1"
    local permit_root_login_no="no"

    if ssh_daemon_managed_fragment_has_permit_root_disabled; then
        permit_root_login_no="yes"
    fi

    ssh_write_daemon_managed_fragment "${permit_root_login_no}" "${username}" || return 1
    ssh_reload_safely || return 1
}


ssh_ensure_daemon_root_login_disabled() {
    ssh_write_daemon_managed_fragment "yes" || return 1
    ssh_reload_safely || return 1
}


ssh_validate_daemon_config() {
    # SSH mistakes can lock out remote administration; validation is mandatory
    # before changing the running daemon.
    /usr/sbin/sshd -t
}


ssh_reload_safely() {
    ssh_validate_daemon_config || return 1
    svc_reload ssh
}

