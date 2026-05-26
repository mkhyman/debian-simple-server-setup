#!/usr/bin/env bash
###############################################################################
# REDIS HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

redis_restart_safely() {
    # Redis has no consistently useful offline config validator on the target
    # Debian baseline, so the risky part is kept behind one wrapper for now.
    svc_restart redis-server
}

