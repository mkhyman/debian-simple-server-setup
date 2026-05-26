#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

read -rp "Primary hostname, e.g. shop.example.com: " hostname

if ! site_validate_hostname "${hostname}"; then
    log_fail "Invalid hostname: ${hostname}"
fi

default_site_user="$(site_hostname_to_username "${hostname}")"
read -rp "Linux site username [${default_site_user}]: " site_user
site_user="${site_user:-${default_site_user}}"

if ! user_validate_system_username "${site_user}"; then
    log_fail "Invalid Linux username: ${site_user}"
fi

if user_system_user_exists "${site_user}"; then
    log_info "Website user found: ${site_user}"
    prompt_confirm "Continue managing this existing user?" || exit 0
else
    log_warn "Website user does not currently exist: ${site_user}"
    prompt_confirm "Create this website user?" || exit 0
    user_ensure_system_user "${site_user}" || log_fail "Could not create website user ${site_user}. Website directories were not created."
fi

read -rp "Laravel site directories? [Y/n]: " is_laravel
is_laravel="${is_laravel:-Y}"

site_ensure_directories "${site_user}" "${is_laravel}" || log_fail "Could not create website directories for ${site_user}. ACLs and optional tooling were not applied."
site_ensure_acls "${site_user}" "${is_laravel}" || log_fail "Could not apply website ACLs for ${site_user}. Apache may not be able to read the site until permissions are fixed."

home_dir="$(site_home_for_user "${site_user}")"

if [[ -s "${home_dir}/.nvm/nvm.sh" ]]; then
    log_info "NVM already installed for ${site_user}."
else
    if prompt_confirm "Install nvm for ${site_user}?"; then
        log_run su - "${site_user}" -c 'export PROFILE="$HOME/.bashrc"; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' || log_fail "NVM install failed for ${site_user}. Website user/directories remain in place; rerun this script to retry Node setup."
    fi
fi

read -rp "Node version to install for ${site_user}, e.g. --lts, 20, 22, or blank to skip: " node_version
if [[ -n "${node_version}" ]]; then
    log_run su - "${site_user}" -c "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install ${node_version}; nvm alias default ${node_version}" || log_fail "Node install failed for ${site_user}. Website user/directories remain in place; rerun this script to retry Node setup."
fi

log_ok "Website user prepared: ${site_user}"
log_info "Site root: $(site_root_for_user "${site_user}")"
