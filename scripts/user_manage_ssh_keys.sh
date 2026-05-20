#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

read -rp "Linux username whose SSH keys should be managed: " username

if ! validate_linux_username "${username}"; then
    fail "Invalid Linux username: ${username}"
fi

if ! linux_user_exists "${username}"; then
    fail "User does not exist: ${username}"
fi

ensure_ssh_authorized_keys_file "${username}" || fail "Could not prepare authorized_keys for ${username}. No SSH key changes were made."

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
            show_authorized_keys "${username}" || fail "Could not show SSH keys for ${username}. No changes were made."
            ;;
        2)
            read -rp "Paste public key: " public_key
            [[ -n "${public_key}" ]] || { warn "No key supplied."; continue; }
            add_ssh_public_key "${username}" "${public_key}" || fail "Could not add SSH key for ${username}. Existing keys should be unchanged."
            ok "SSH key added."
            ;;
        3)
            warn "This replaces all existing authorized_keys entries for ${username}."
            read -rp "Type REPLACE_KEYS to continue: " typed
            [[ "${typed}" == "REPLACE_KEYS" ]] || { info "Aborted."; continue; }
            read -rp "Paste replacement public key: " public_key
            [[ -n "${public_key}" ]] || { warn "No key supplied."; continue; }
            replace_ssh_public_keys "${username}" "${public_key}" || fail "Could not replace SSH keys for ${username}. A backup should exist if the original authorized_keys was present."
            ok "SSH keys replaced."
            ;;
        4)
            show_authorized_keys "${username}" || fail "Could not show SSH keys for ${username}. No changes were made."
            read -rp "Key number to remove: " key_number
            confirm "Remove key number ${key_number} for ${username}?" || continue
            remove_authorized_key_by_number "${username}" "${key_number}" || fail "Could not remove SSH key number ${key_number} for ${username}. A backup should exist if authorized_keys was present."
            ok "SSH key removed."
            ;;
        [Qq])
            ok "Finished SSH key management."
            exit 0
            ;;
        *)
            warn "Invalid choice."
            ;;
    esac
done
