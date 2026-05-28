#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

if command -v composer >/dev/null 2>&1; then
    log_info "Composer is already installed."
    log_run env COMPOSER_ALLOW_SUPERUSER=1 composer --version || log_fail "Composer was installed but could not be executed from PATH."
    prompt_confirm "Update/reinstall Composer?" || exit 0
fi

log_run apt-get update || log_fail "apt-get update failed. Composer prerequisites were not installed."
log_run apt-get install -y curl php-cli unzip || log_fail "Could not install Composer prerequisites. Composer installer was not downloaded."

expected_signature="$(curl -fsSL https://composer.github.io/installer.sig 2>>"${LOG_FILE}")" || log_fail "Could not download Composer installer signature. Composer was not installed."
log_run php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');" || log_fail "Could not download Composer installer. Composer was not installed."
actual_signature="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');" 2>>"${LOG_FILE}")" || log_fail "Could not calculate Composer installer signature. Composer was not installed."

if [[ "${expected_signature}" != "${actual_signature}" ]]; then
    rm -f /tmp/composer-setup.php
    log_fail "Invalid Composer installer signature. Installer was removed and Composer was not installed."
fi

log_run php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer || log_fail "Composer install failed. Check the installer output in the log; /usr/local/bin/composer may be absent or unchanged."
rm -f /tmp/composer-setup.php

log_run env COMPOSER_ALLOW_SUPERUSER=1 composer --version || log_fail "Composer was installed but could not be executed from PATH."
log_ok "Composer installed."
