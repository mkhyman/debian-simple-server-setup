#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

if command -v composer >/dev/null 2>&1; then
    info "Composer is already installed."
    COMPOSER_ALLOW_SUPERUSER=1 composer --version | tee -a "${LOG_FILE}" || fail "Composer was installed but could not be executed from PATH."
    confirm "Update/reinstall Composer?" || exit 0
fi

run apt-get update || fail "apt-get update failed. Composer prerequisites were not installed."
run apt-get install -y curl php-cli unzip || fail "Could not install Composer prerequisites. Composer installer was not downloaded."

expected_signature="$(curl -fsSL https://composer.github.io/installer.sig)" || fail "Could not download Composer installer signature. Composer was not installed."
php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');" || fail "Could not download Composer installer. Composer was not installed."
actual_signature="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")" || fail "Could not calculate Composer installer signature. Composer was not installed."

if [[ "${expected_signature}" != "${actual_signature}" ]]; then
    rm -f /tmp/composer-setup.php
    fail "Invalid Composer installer signature. Installer was removed and Composer was not installed."
fi

run php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer || fail "Composer install failed. Check the installer output in the log; /usr/local/bin/composer may be absent or unchanged."
rm -f /tmp/composer-setup.php

COMPOSER_ALLOW_SUPERUSER=1 composer --version | tee -a "${LOG_FILE}" || fail "Composer was installed but could not be executed from PATH."
ok "Composer installed."
