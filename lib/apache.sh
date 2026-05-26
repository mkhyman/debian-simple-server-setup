#!/usr/bin/env bash
###############################################################################
# APACHE HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

apache_validate_config() {
    # Apache is shared by all hosted sites, so one bad generated vhost must be
    # caught before the daemon is reloaded and every site is put at risk.
    log_run apache2ctl configtest
}


apache_reload_safely() {
    apache_validate_config || return 1
    svc_reload apache2
}


apache_restart_safely() {
    apache_validate_config || return 1
    svc_restart apache2
}

