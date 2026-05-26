#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/common.sh" "$@"
user_require_root

menu_entries=(
    "core|core_base_system.sh|Base system setup"
    "core|core_firewall.sh|Configure UFW firewall"
    "core|core_webstack_apache_php_mariadb_redis.sh|Install Apache, PHP-FPM, MariaDB TLS and Redis"
    "core|core_composer.sh|Install Composer"
    "core|core_disable_root_ssh.sh|Disable root SSH login"
    "core|core_health_check.sh|Run core system health check"

    "user|user_admin.sh|Create/update admin user"
    "user|user_website.sh|Create/update website user"
    "user|user_manage_ssh_keys.sh|Manage SSH keys for a Linux user"
    "user|user_health_check.sh|Run Linux user health check"

    "website|website_import_paid_certificate.sh|Import paid SSL certificate"
    "website|website_create_https_vhost.sh|Create HTTPS-only Apache vhost"
    "website|website_create_mariadb_user.sh|Create MariaDB database/user requiring SSL"
    "website|website_health_check.sh|Run website health check"
)

run_selected_script() {
    local rel_script="$1"
    local description="$2"

    if [[ ! -x "${REPO_ROOT}/scripts/${rel_script}" ]]; then
        log_warn "Script is missing or not executable: scripts/${rel_script}"
        read -rp "Press Enter to continue..."
        return 1
    fi

    echo
    echo "Selected: scripts/${rel_script}"
    echo "${description}"
    echo
    read -rp "Run with verbose command output? [y/N]: " verbose_answer

    if [[ "${verbose_answer}" =~ ^[Yy]$ ]]; then
        "${REPO_ROOT}/scripts/${rel_script}" --verbose
    else
        "${REPO_ROOT}/scripts/${rel_script}"
    fi
}

if ! state_base_system_complete; then
    echo
    echo "Base system setup has not been completed yet."
    echo
    echo "This must be log_run before the other toolkit scripts because it creates:"
    echo "  - the ${SERVER_ADMIN_GROUP} group"
    echo "  - runtime directories under ${SERVER_ADMIN_DIR}"
    echo "  - toolkit permissions"
    echo "  - base packages"
    echo "  - fail2ban and unattended security updates"
    echo

    if prompt_confirm "Run core_base_system.sh now?"; then
        run_selected_script "core_base_system.sh" "Base system setup"
    else
        echo
        echo "Base system setup is required before using the rest of the toolkit."
        exit 0
    fi
fi

while true; do
    clear
    echo "Server Setup Toolkit ${SERVER_SETUP_TOOLKIT_VERSION}"
    echo

    index=1
    for group in core user website; do
        case "${group}" in
            core) echo "Core" ;;
            user) echo "User" ;;
            website) echo "Website" ;;
        esac
        echo "-------"

        for entry in "${menu_entries[@]}"; do
            IFS='|' read -r entry_group file description <<<"${entry}"
            if [[ "${entry_group}" == "${group}" ]]; then
                printf "  %2d) %-45s %s\n" "${index}" "${file}" "${description}"
                index=$((index+1))
            fi
        done
        echo
    done

    echo "  Q) Quit"
    echo
    read -rp "Choose script to log_run: " choice

    if [[ "${choice}" =~ ^[Qq]$ ]]; then
        log_ok "Exiting."
        exit 0
    fi

    if [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#menu_entries[@]} )); then
        log_warn "Invalid choice."
        read -rp "Press Enter to continue..."
        continue
    fi

    IFS='|' read -r _group file description <<<"${menu_entries[$((choice-1))]}"

    run_selected_script "${file}" "${description}"

    echo
    log_ok "Finished: ${file}"
    read -rp "Press Enter to return to menu..."
done
