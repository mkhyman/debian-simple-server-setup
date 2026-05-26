#!/usr/bin/env bash
###############################################################################
# SERVICES HELPERS
#
# Generic service primitives. These functions intentionally do not log: callers
# decide what the operation means and what should be shown to the user.
###############################################################################

svc_enable_now() {
    local service_name="$1"
    systemctl enable --now "${service_name}"
}


svc_restart() {
    local service_name="$1"
    systemctl restart "${service_name}"
}


svc_reload() {
    local service_name="$1"
    systemctl reload "${service_name}"
}


svc_is_active() {
    local service_name="$1"
    systemctl is-active --quiet "${service_name}"
}
