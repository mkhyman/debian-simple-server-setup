#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# COMPOSER
#
# Composer is installed globally for admin convenience, but project-level
# composer install/update should be run as the relevant site user, not root.
###############################################################################

if command -v composer >/dev/null 2>&1; then
    info "Composer is already installed."
    COMPOSER_ALLOW_SUPERUSER=1 composer --version | tee -a "${LOG_FILE}"

    if ! confirm "Update/reinstall Composer?"; then
        ok "Composer left unchanged."
        exit 0
    fi
fi

run apt-get update
run apt-get install -y curl php-cli unzip

info "Downloading and verifying Composer installer signature."
EXPECTED_SIGNATURE="$(curl -fsSL https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

if [[ "${EXPECTED_SIGNATURE}" != "${ACTUAL_SIGNATURE}" ]]; then
    rm -f /tmp/composer-setup.php
    fail "Invalid Composer installer signature."
fi

run php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f /tmp/composer-setup.php

# Composer warns when run as root. This one command only checks the installed
# version; it does not run project scripts or install third-party packages.
COMPOSER_ALLOW_SUPERUSER=1 composer --version | tee -a "${LOG_FILE}"

ok "Composer installed."
