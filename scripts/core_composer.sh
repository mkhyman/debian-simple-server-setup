#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

if command -v composer >/dev/null 2>&1; then
    info "Composer is already installed."
    COMPOSER_ALLOW_SUPERUSER=1 composer --version | tee -a "${LOG_FILE}"
    confirm "Update/reinstall Composer?" || exit 0
fi

run apt-get update || fail "apt-get update failed."
run apt-get install -y curl php-cli unzip || fail "Could not install Composer prerequisites."

expected_signature="$(curl -fsSL https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
actual_signature="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

if [[ "${expected_signature}" != "${actual_signature}" ]]; then
    rm -f /tmp/composer-setup.php
    fail "Invalid Composer installer signature."
fi

run php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer || fail "Composer install failed."
rm -f /tmp/composer-setup.php

COMPOSER_ALLOW_SUPERUSER=1 composer --version | tee -a "${LOG_FILE}"
ok "Composer installed."
