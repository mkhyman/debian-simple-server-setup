#!/usr/bin/env bash
###############################################################################
# PROMPTS HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

prompt_confirm() {
    local prompt="$1"

    if [[ "${INTERACTIVE_CONFIRMATIONS}" != "yes" ]]; then
        return 0
    fi

    read -rp "${prompt} [y/N]: " answer
    [[ "${answer}" =~ ^[Yy]$ ]]
}

