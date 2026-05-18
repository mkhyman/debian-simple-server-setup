#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# INTERACTIVE SETUP MENU
#
# This is intentionally a thin wrapper. It does not hide what the scripts do;
# it simply reduces typo friction and makes the toolkit easier to use later.
###############################################################################

scripts=(
    "01_core_base_admin_security.sh|Core setup|Create admin user, SSH key login, fail2ban, unattended security updates"
    "02_core_firewall.sh|Core setup|Configure UFW without resetting existing rules"
    "03_core_webstack_apache_php_mariadb_redis.sh|Core setup|Install Apache, PHP-FPM, MariaDB TLS and Redis"
    "04_core_composer.sh|Core setup|Install Composer"
    "05_core_disable_root_ssh.sh|Core setup|Disable root SSH login after admin login is tested"
    "site_create_website_user.sh|Website management|Create per-site Linux user and folder structure"
    "site_import_paid_certificate.sh|Website management|Import and normalize paid SSL certificate files"
    "site_create_https_vhost.sh|Website management|Create HTTPS-only Apache vhost with PHP-FPM pool"
    "site_create_mariadb_user.sh|Website management|Create MariaDB database/user requiring SSL"
)

while true; do
    clear
    echo "Server Setup Toolkit ${SERVER_SETUP_TOOLKIT_VERSION}"
    echo
    echo "Core setup"
    echo "----------"

    n=1
    for entry in "${scripts[@]}"; do
        IFS='|' read -r file group description <<<"${entry}"
        if [[ "${group}" == "Core setup" ]]; then
            printf "  %2d) %-48s %s\n" "${n}" "${file}" "${description}"
        fi
        n=$((n+1))
    done

    echo
    echo "Website management"
    echo "------------------"

    n=1
    for entry in "${scripts[@]}"; do
        IFS='|' read -r file group description <<<"${entry}"
        if [[ "${group}" == "Website management" ]]; then
            printf "  %2d) %-48s %s\n" "${n}" "${file}" "${description}"
        fi
        n=$((n+1))
    done

    echo
    echo "  Q) Quit"
    echo
    read -rp "Choose script to run: " choice

    if [[ "${choice}" =~ ^[Qq]$ ]]; then
        ok "Exiting."
        exit 0
    fi

    if [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#scripts[@]} )); then
        warn "Invalid choice."
        read -rp "Press Enter to continue..."
        continue
    fi

    IFS='|' read -r file group description <<<"${scripts[$((choice-1))]}"

    if [[ ! -x "${SCRIPT_DIR}/${file}" ]]; then
        warn "Script is missing or not executable: ${file}"
        read -rp "Press Enter to continue..."
        continue
    fi

    echo
    echo "Selected: ${file}"
    echo "${description}"
    echo
    read -rp "Run with verbose command output? [y/N]: " verbose_answer

    if [[ "${verbose_answer}" =~ ^[Yy]$ ]]; then
        "${SCRIPT_DIR}/${file}" --verbose
    else
        "${SCRIPT_DIR}/${file}"
    fi

    echo
    ok "Finished: ${file}"
    read -rp "Press Enter to return to menu..."
done
