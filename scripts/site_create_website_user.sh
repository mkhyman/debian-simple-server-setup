#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# CREATE WEBSITE USER
#
# Creates the per-site Linux user and standard hosting directory structure.
#
# The default username is derived from the full hostname, not only the subdomain,
# to avoid collisions such as shop.domain1.co.uk and shop.domain2.co.uk.
###############################################################################

read -rp "Primary hostname, e.g. shop.example.com: " HOSTNAME
validate_hostname "${HOSTNAME}"

DEFAULT_SITE_USER="$(hostname_to_username "${HOSTNAME}")"
read -rp "Linux site username [${DEFAULT_SITE_USER}]: " SITE_USER
SITE_USER="${SITE_USER:-${DEFAULT_SITE_USER}}"

if [[ ! "${SITE_USER}" =~ ^[a-z_][a-z0-9_-]{1,31}$ ]]; then
    fail "Invalid Linux username after conversion: ${SITE_USER}"
fi

SITE_HOME="${SITE_BASE_DIR}/${SITE_USER}"

if id "${SITE_USER}" &>/dev/null; then
    info "User ${SITE_USER} already exists."
else
    info "Creating site user ${SITE_USER} for ${HOSTNAME}."
    run useradd -m -d "${SITE_HOME}" -s /bin/bash "${SITE_USER}"
fi

info "Creating standard site directories."
install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}"
install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}/${SITE_DOC_DIR}"
install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}/${SITE_LOG_DIR}"
install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}/${SITE_TMP_DIR}"
install -d -m 700 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}/.ssh"

AUTHORIZED_KEYS="${SITE_HOME}/.ssh/authorized_keys"
touch "${AUTHORIZED_KEYS}"
chown "${SITE_USER}:${SITE_USER}" "${AUTHORIZED_KEYS}"
chmod 600 "${AUTHORIZED_KEYS}"

read -rp "Add SSH public key for ${SITE_USER}? Paste key or leave blank: " SITE_KEY
if [[ -n "${SITE_KEY}" ]]; then
    if grep -qxF "${SITE_KEY}" "${AUTHORIZED_KEYS}"; then
        info "SSH key already present for ${SITE_USER}."
    else
        echo "${SITE_KEY}" >> "${AUTHORIZED_KEYS}"
        ok "Added SSH key for ${SITE_USER}."
    fi
fi

# NVM is intentionally installed per site user, because different Laravel/Vite
# projects may need different Node versions.
if [[ -s "${SITE_HOME}/.nvm/nvm.sh" ]]; then
    info "NVM already installed for ${SITE_USER}."
else
    if confirm "Install nvm for ${SITE_USER}?"; then
        run su - "${SITE_USER}" -c 'export PROFILE="$HOME/.bashrc"; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
    fi
fi

read -rp "Node version to install for ${SITE_USER}, e.g. --lts, 20, 22, or blank to skip: " NODE_VERSION
if [[ -n "${NODE_VERSION}" ]]; then
    run su - "${SITE_USER}" -c "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install ${NODE_VERSION}; nvm alias default ${NODE_VERSION}"
fi

chown -R "${SITE_USER}:${SITE_USER}" "${SITE_HOME}"

ok "Website user ${SITE_USER} prepared at ${SITE_HOME}."
info "Site path: ${SITE_HOME}/${SITE_DOC_DIR}"
