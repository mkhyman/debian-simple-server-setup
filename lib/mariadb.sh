#!/usr/bin/env bash
###############################################################################
# MARIADB HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

mariadb_validate_config() {
    # MariaDB validation differs a little across releases. Prefer the explicit
    # validator when present, and fall back to the server's config-parsing path.
    if mariadbd --help --verbose 2>&1 | grep -q -- '--validate-config'; then
        log_run mariadbd --validate-config
    else
        log_run mysqld --verbose --help
    fi
}


mariadb_restart_safely() {
    mariadb_validate_config || return 1
    svc_restart mariadb
}

