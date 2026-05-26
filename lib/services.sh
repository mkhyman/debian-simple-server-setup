#!/usr/bin/env bash
###############################################################################
# SERVICES HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

svc_enable_now() {
    local service_name="$1"

    # Centralising service control gives future Debian changes a single edit
    # point instead of leaving package scripts full of init-system assumptions.
    log_run systemctl enable --now "${service_name}"
}


svc_restart() {
    local service_name="$1"

    # Restart is intentionally wrapped because it is disruptive: callers should
    # read as operational intent, while this function owns the platform detail.
    log_run systemctl restart "${service_name}"
}


svc_reload() {
    local service_name="$1"

    # Reload is preferred where possible because it preserves live connections;
    # this wrapper keeps that policy visible and easy to change globally.
    log_run systemctl reload "${service_name}"
}

