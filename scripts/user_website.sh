#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

read -rp "Primary hostname, e.g. shop.example.com: " hostname

if ! validate_hostname "${hostname}"; then
    fail "Invalid hostname: ${hostname}"
fi

default_site_user="$(hostname_to_username "${hostname}")"
read -rp "Linux site username [${default_site_user}]: " site_user
site_user="${site_user:-${default_site_user}}"

if ! validate_linux_username "${site_user}"; then
    fail "Invalid Linux username: ${site_user}"
fi

if linux_user_exists "${site_user}"; then
    info "Website user found: ${site_user}"
    confirm "Continue managing this existing user?" || exit 0
else
    warn "Website user does not currently exist: ${site_user}"
    confirm "Create this website user?" || exit 0
    ensure_linux_user "${site_user}" || fail "Could not create user ${site_user}."
fi

read -rp "Laravel site directories? [Y/n]: " is_laravel
is_laravel="${is_laravel:-Y}"

ensure_website_directories "${site_user}" "${is_laravel}" || fail "Could not create website directories."
ensure_website_acls "${site_user}" "${is_laravel}" || fail "Could not apply website ACLs."

home_dir="$(site_home_for_user "${site_user}")"

if [[ -s "${home_dir}/.nvm/nvm.sh" ]]; then
    info "NVM already installed for ${site_user}."
else
    if confirm "Install nvm for ${site_user}?"; then
        run su - "${site_user}" -c 'export PROFILE="$HOME/.bashrc"; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' || fail "NVM install failed."
    fi
fi

read -rp "Node version to install for ${site_user}, e.g. --lts, 20, 22, or blank to skip: " node_version
if [[ -n "${node_version}" ]]; then
    run su - "${site_user}" -c "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install ${node_version}; nvm alias default ${node_version}" || fail "Node install failed."
fi

ok "Website user prepared: ${site_user}"
info "Site root: $(site_root_for_user "${site_user}")"
