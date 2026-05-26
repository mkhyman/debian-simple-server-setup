#!/usr/bin/env bash
###############################################################################
# FPM HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

fpm_validate_config() {
    local php_version="$1"

    # Per-site pools are generated dynamically, so test the complete PHP-FPM
    # configuration before restarting the version that serves those pools.
    "php-fpm${php_version}" -t
}


fpm_restart_safely() {
    local php_version="$1"

    fpm_validate_config "${php_version}" || return 1
    svc_restart "php${php_version}-fpm"
}


fpm_version_exists() {
    local php_version="$1"
    [[ -d "/etc/php/${php_version}/fpm" ]]
}

