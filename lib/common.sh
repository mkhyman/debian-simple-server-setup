#!/usr/bin/env bash
###############################################################################
# COMMON INCLUDE
#
# This file is the public include point for scripts. It resolves repository
# configuration, initialises logging, then sources focused helper libraries.
# Implementation belongs in the focused lib/*.sh files so common.sh does not
# become a hiding place for unrelated workflow logic.
###############################################################################

set -euo pipefail

_common_source="${BASH_SOURCE[0]}"
_common_dir="$(cd "$(dirname "${_common_source}")" && pwd)"

# Caller is normally either run_server_setup.sh in repo root or a script under
# scripts/. Work out the repo root without assuming an absolute clone path.
_caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
_caller_dir="$(cd "$(dirname "${_caller}")" && pwd)"

if [[ -f "${_caller_dir}/config.sh" ]]; then
    REPO_ROOT="${_caller_dir}"
elif [[ -f "${_caller_dir}/../config.sh" ]]; then
    REPO_ROOT="$(cd "${_caller_dir}/.." && pwd)"
elif [[ -f "${_common_dir}/../config.sh" ]]; then
    REPO_ROOT="$(cd "${_common_dir}/.." && pwd)"
else
    cat >&2 <<'EOF'
[ERROR] config.sh not found.

Create it from the example:

  cp config.example.sh config.sh
  nano config.sh
EOF
    exit 1
fi

source "${REPO_ROOT}/config.sh"

VERBOSE="no"
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE="yes"
fi

SCRIPT_NAME="$(basename "${_caller}" .sh)"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"

source "${_common_dir}/logging.sh"
source "${_common_dir}/prompts.sh"
source "${_common_dir}/services.sh"
source "${_common_dir}/users.sh"
source "${_common_dir}/files.sh"
source "${_common_dir}/state.sh"
source "${_common_dir}/apache.sh"
source "${_common_dir}/fpm.sh"
source "${_common_dir}/mariadb.sh"
source "${_common_dir}/redis.sh"
source "${_common_dir}/ssh.sh"
source "${_common_dir}/sites.sh"
source "${_common_dir}/certificates.sh"

log_init
