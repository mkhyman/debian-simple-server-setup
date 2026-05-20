#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

MH_WEBSITE_HC_PASS_COUNT=0
MH_WEBSITE_HC_WARN_COUNT=0
MH_WEBSITE_HC_FAIL_COUNT=0

health_ok() { ok "$*"; MH_WEBSITE_HC_PASS_COUNT=$((MH_WEBSITE_HC_PASS_COUNT+1)); }
health_warn() { warn "$*"; MH_WEBSITE_HC_WARN_COUNT=$((MH_WEBSITE_HC_WARN_COUNT+1)); }
health_fail() { echo "[FAIL] $*"; echo "[FAIL] $*" >>"${LOG_FILE}"; MH_WEBSITE_HC_FAIL_COUNT=$((MH_WEBSITE_HC_FAIL_COUNT+1)); }

maybe_fix_dir() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "${reason}"
    if confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        install -d -m "${mode}" -o "${owner}" -g "${group}" "${path}" || { health_fail "Could not fix ${path}."; return 1; }
        health_ok "Fixed ${path}."
    fi
}

maybe_fix_file_mode_owner() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    [[ -f "${path}" ]] || return 0
    echo "${reason}"
    if confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        chown "${owner}:${group}" "${path}" || { health_fail "Could not chown ${path}."; return 1; }
        chmod "${mode}" "${path}" || { health_fail "Could not chmod ${path}."; return 1; }
        health_ok "Fixed ${path}."
    fi
}

check_dir() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local reason="$5"
    local interactive_fix="$6"

    if [[ ! -d "${path}" ]]; then
        health_fail "Missing directory: ${path}"
        maybe_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        return 0
    fi

    local actual_mode actual_owner actual_group
    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    if [[ "${actual_mode}" == "${expected_mode}" && "${actual_owner}" == "${expected_owner}" && "${actual_group}" == "${expected_group}" ]]; then
        health_ok "${path} has expected owner and mode."
    else
        health_fail "${path} is ${actual_owner}:${actual_group} ${actual_mode}; expected ${expected_owner}:${expected_group} ${expected_mode}."
        maybe_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
    fi
}

check_acl_contains() {
    local path="$1"
    local acl_pattern="$2"
    local description="$3"
    local site_user="$4"
    local is_laravel="$5"
    local interactive_fix="$6"

    if ! command -v getfacl >/dev/null 2>&1; then
        health_warn "Cannot check ACLs because getfacl is not installed."
        return 0
    fi

    if getfacl -cp "${path}" 2>/dev/null | grep -Eq "${acl_pattern}"; then
        health_ok "${description}"
    else
        health_fail "Missing ACL: ${description}"
        if [[ "${interactive_fix}" == "yes" ]]; then
            echo "Apache should receive only the access it needs while PHP runs as the site user."
            if confirm "Re-apply toolkit ACLs for ${site_user}?"; then
                ensure_website_acls "${site_user}" "${is_laravel}" || { health_fail "Could not re-apply website ACLs."; return 1; }
                health_ok "Re-applied website ACLs for ${site_user}."
            fi
        fi
    fi
}

check_file_not_world_readable() {
    local path="$1"
    local site_user="$2"
    local interactive_fix="$3"

    [[ -f "${path}" ]] || return 0

    local mode owner group others_digit
    mode="$(stat -c '%a' "${path}")"
    owner="$(stat -c '%U' "${path}")"
    group="$(stat -c '%G' "${path}")"
    others_digit="${mode: -1}"

    if (( others_digit == 0 )); then
        health_ok "${path} is not world-readable."
    else
        health_fail "${path} is ${owner}:${group} ${mode}; it should not be world-readable."
        maybe_fix_file_mode_owner "${path}" 600 "${site_user}" "${site_user}" ".env often contains secrets, so other local users should not be able to read it." "${interactive_fix}"
    fi
}

main_website_health_check() {
    local interactive_fix="no"
    local site_user=""
    local is_laravel=""
    local arg
    local site_home site_root detected_laravel docroot logs tmpdir
    local php_version candidate pool_file
    local -a pool_files

    for arg in "$@"; do
        case "${arg}" in
            --interactive-fix) interactive_fix="yes" ;;
            *) site_user="${arg}" ;;
        esac
    done

    if [[ -z "${site_user}" ]]; then
        read -rp "Linux site username to check: " site_user
    fi

    validate_linux_username "${site_user}" || fail "Invalid Linux username: ${site_user}"

    site_home="$(site_home_for_user "${site_user}")"
    site_root="$(site_root_for_user "${site_user}")"

    if [[ -f "${site_root}/artisan" || -d "${site_root}/bootstrap/cache" || -d "${site_root}/storage" ]]; then
        detected_laravel="Y"
    else
        detected_laravel="N"
    fi

    read -rp "Treat as Laravel site? [${detected_laravel}]: " is_laravel
    is_laravel="${is_laravel:-${detected_laravel}}"

    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"
    logs="${site_home}/${SITE_LOG_DIR}"
    tmpdir="${site_home}/${SITE_TMP_DIR}"

    echo
    info "Running website health check for ${site_user}."
    if [[ "${interactive_fix}" == "yes" ]]; then
        info "Interactive fixes are enabled for low-risk filesystem and ACL issues."
    else
        info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
    fi
    echo

    if ! linux_user_exists "${site_user}"; then
        health_fail "Linux site user does not exist: ${site_user}"
        info "Website health check complete: ${MH_WEBSITE_HC_PASS_COUNT} ok, ${MH_WEBSITE_HC_WARN_COUNT} warnings, ${MH_WEBSITE_HC_FAIL_COUNT} failures."
        exit 1
    fi
    health_ok "Linux site user exists: ${site_user}"

    check_dir "${site_home}" 750 "${site_user}" "${site_user}" "The site home should be private to the site user, with Apache granted access through ACLs only where needed." "${interactive_fix}"
    check_dir "${site_root}" 750 "${site_user}" "${site_user}" "The site root should be owned by the PHP-FPM site user, not by Apache." "${interactive_fix}"
    check_dir "${docroot}" 750 "${site_user}" "${site_user}" "Apache should be able to read the public document root through ACLs without owning the whole site." "${interactive_fix}"
    check_dir "${logs}" 750 "${site_user}" "${site_user}" "Logs live under the site home so they remain grouped with the site and easy to inspect." "${interactive_fix}"
    check_dir "${tmpdir}" 750 "${site_user}" "${site_user}" "Per-site temporary storage avoids sharing writable runtime paths across sites." "${interactive_fix}"

    if [[ "${is_laravel}" =~ ^[Yy]$ ]]; then
        check_dir "${site_root}/storage" 775 "${site_user}" "${site_user}" "Laravel storage must be writable by the PHP-FPM site user for cache, sessions, logs and uploads." "${interactive_fix}"
        check_dir "${site_root}/bootstrap/cache" 775 "${site_user}" "${site_user}" "Laravel bootstrap/cache must be writable by the PHP-FPM site user during deployment and cache rebuilds." "${interactive_fix}"
        [[ -f "${site_root}/artisan" ]] && health_ok "Laravel artisan file exists." || health_warn "Laravel artisan file not found; this may be normal before code is deployed."
        [[ -d "${site_root}/public" ]] && health_ok "Laravel public directory exists." || health_fail "Laravel public directory is missing: ${site_root}/public"
    fi

    check_file_not_world_readable "${site_root}/.env" "${site_user}" "${interactive_fix}"

    if command -v getfacl >/dev/null 2>&1; then
        check_acl_contains "${site_home}" "^user:${APACHE_RUN_USER}:--x$" "Apache has traversal-only access to ${site_home}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        check_acl_contains "${site_root}" "^user:${APACHE_RUN_USER}:--x$" "Apache has traversal-only access to ${site_root}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        check_acl_contains "${docroot}" "^user:${APACHE_RUN_USER}:r-x$" "Apache has read/execute access to ${docroot}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        check_acl_contains "${logs}" "^user:${APACHE_RUN_USER}:rwx$" "Apache can write site logs under ${logs}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        check_acl_contains "${tmpdir}" "^user:${APACHE_RUN_USER}:rwx$" "Apache can use the site's temporary directory." "${site_user}" "${is_laravel}" "${interactive_fix}"
    fi

    pool_files=()
    for php_version in "${PHP_VERSIONS[@]}"; do
        candidate="/etc/php/${php_version}/fpm/pool.d/${site_user}.conf"
        if [[ -f "${candidate}" ]]; then
            pool_files+=("${candidate}")
        fi
    done

    if [[ "${#pool_files[@]}" -eq 0 ]]; then
        health_warn "No PHP-FPM pool found for ${site_user}; this may be normal before vhost creation."
    else
        for pool_file in "${pool_files[@]}"; do
            health_ok "PHP-FPM pool exists: ${pool_file}"
            if grep -Eq "^user[[:space:]]*=[[:space:]]*${site_user}$" "${pool_file}"; then
                health_ok "${pool_file} runs PHP as ${site_user}."
            else
                health_fail "${pool_file} does not appear to run PHP as ${site_user}."
            fi
        done
    fi

    if compgen -G "/etc/apache2/sites-enabled/*${site_user}*" >/dev/null; then
        health_ok "An enabled Apache site appears to reference ${site_user}."
    else
        if grep -Rqs "${docroot}" /etc/apache2/sites-enabled 2>/dev/null; then
            health_ok "An enabled Apache site points at ${docroot}."
        else
            health_warn "No enabled Apache site appears to point at ${docroot}."
        fi
    fi

    echo
    info "Website health check complete: ${MH_WEBSITE_HC_PASS_COUNT} ok, ${MH_WEBSITE_HC_WARN_COUNT} warnings, ${MH_WEBSITE_HC_FAIL_COUNT} failures."

    if (( MH_WEBSITE_HC_FAIL_COUNT > 0 )); then
        exit 1
    fi
}

main_website_health_check "$@"
