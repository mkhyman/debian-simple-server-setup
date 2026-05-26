#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

read -rp "Linux username whose SSH keys should be managed: " username

if ! user_validate_system_username "${username}"; then
    log_fail "Invalid Linux username: ${username}"
fi

if ! user_system_user_exists "${username}"; then
    log_fail "User does not exist: ${username}"
fi

ssh_ensure_authorized_keys_file "${username}" || log_fail "Could not prepare authorized_keys for ${username}. No SSH key changes were made."

while true; do
    echo
    echo "SSH key management for ${username}"
    echo
    echo "1) Show current keys"
    echo "2) Add/paste a public key"
    echo "3) Replace all keys with one public key"
    echo "4) Remove a key by number"
    echo "Q) Quit"
    echo
    read -rp "Choose option: " choice

    case "${choice}" in
        1)
            ssh_show_authorized_keys "${username}" || log_fail "Could not show SSH keys for ${username}. No changes were made."
            ;;
        2)
            read -rp "Paste public key: " public_key
            [[ -n "${public_key}" ]] || { log_warn "No key supplied."; continue; }
            ssh_add_public_key "${username}" "${public_key}" || log_fail "Could not add SSH key for ${username}. Existing keys should be unchanged."
            log_ok "SSH key added."
            ;;
        3)
            log_warn "This replaces all existing authorized_keys entries for ${username}."
            read -rp "Type REPLACE_KEYS to continue: " typed
            [[ "${typed}" == "REPLACE_KEYS" ]] || { log_info "Aborted."; continue; }
            read -rp "Paste replacement public key: " public_key
            [[ -n "${public_key}" ]] || { log_warn "No key supplied."; continue; }
            ssh_replace_public_keys "${username}" "${public_key}" || log_fail "Could not replace SSH keys for ${username}. A backup should exist if the original authorized_keys was present."
            log_ok "SSH keys replaced."
            ;;
        4)
            ssh_show_authorized_keys "${username}" || log_fail "Could not show SSH keys for ${username}. No changes were made."
            read -rp "Key number to remove: " key_number
            prompt_confirm "Remove key number ${key_number} for ${username}?" || continue
            ssh_remove_authorized_key_by_number "${username}" "${key_number}" || log_fail "Could not remove SSH key number ${key_number} for ${username}. A backup should exist if authorized_keys was present."
            log_ok "SSH key removed."
            ;;
        [Qq])
            log_ok "Finished SSH key management."
            exit 0
            ;;
        *)
            log_warn "Invalid choice."
            ;;
    esac
done
