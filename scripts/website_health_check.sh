#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

MH_WEBSITE_HC_PASS_COUNT=0
MH_WEBSITE_HC_WARN_COUNT=0
MH_WEBSITE_HC_FAIL_COUNT=0

website_health_ok() { log_ok "$*"; MH_WEBSITE_HC_PASS_COUNT=$((MH_WEBSITE_HC_PASS_COUNT+1)); }
website_health_warn() { log_warn "$*"; MH_WEBSITE_HC_WARN_COUNT=$((MH_WEBSITE_HC_WARN_COUNT+1)); }
website_health_fail() { echo "[FAIL] $*"; echo "[FAIL] $*" >>"${LOG_FILE}"; MH_WEBSITE_HC_FAIL_COUNT=$((MH_WEBSITE_HC_FAIL_COUNT+1)); }

website_hc_directory_matches_owner_mode() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"

    [[ -d "${path}" ]] || return 1
    [[ "$(stat -c '%U:%G %a' "${path}")" == "${expected_owner}:${expected_group} ${expected_mode}" ]]
}

website_hc_acl_matches() {
    local path="$1"
    local acl_pattern="$2"

    command -v getfacl >/dev/null 2>&1 || return 2
    getfacl -cp "${path}" 2>/dev/null | grep -Eq "${acl_pattern}"
}

website_hc_file_is_world_readable() {
    local path="$1"
    local mode others_digit

    [[ -f "${path}" ]] || return 1
    mode="$(stat -c '%a' "${path}")"
    others_digit="${mode: -1}"
    (( others_digit > 0 ))
}

website_hc_fix_directory_owner_mode() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"

    install -d -m "${mode}" -o "${owner}" -g "${group}" "${path}"
}

website_hc_fix_file_owner_mode() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"

    [[ -f "${path}" ]] || return 1
    chown "${owner}:${group}" "${path}" || return 1
    chmod "${mode}" "${path}"
}

website_hc_offer_directory_fix() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "${reason}"
    if prompt_confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        if website_hc_fix_directory_owner_mode "${path}" "${mode}" "${owner}" "${group}"; then
            website_health_ok "Fixed ${path}."
        else
            website_health_fail "Could not fix ${path}."
        fi
    fi
}

website_hc_offer_file_fix() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"
    local interactive_fix="$6"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    [[ -f "${path}" ]] || return 0
    echo "${reason}"
    if prompt_confirm "Set ${path} to ${owner}:${group} ${mode} now?"; then
        if website_hc_fix_file_owner_mode "${path}" "${mode}" "${owner}" "${group}"; then
            website_health_ok "Fixed ${path}."
        else
            website_health_fail "Could not fix ${path}."
        fi
    fi
}

website_hc_offer_acl_repair() {
    local site_user="$1"
    local is_laravel="$2"
    local interactive_fix="$3"

    [[ "${interactive_fix}" == "yes" ]] || return 0
    echo "Apache should receive only the access it needs while PHP runs as the site user."
    if prompt_confirm "Re-apply website ACLs for ${site_user}?"; then
        if site_ensure_acls "${site_user}" "${is_laravel}"; then
            website_health_ok "Re-applied website ACLs for ${site_user}."
        else
            website_health_fail "Could not re-apply website ACLs."
        fi
    fi
}

website_hc_report_directory_owner_mode() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local reason="$5"
    local interactive_fix="$6"

    if [[ ! -d "${path}" ]]; then
        website_health_fail "Missing directory: ${path}"
        website_hc_offer_directory_fix "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
        return 0
    fi

    if website_hc_directory_matches_owner_mode "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}"; then
        website_health_ok "${path} has expected owner and mode."
        return 0
    fi

    local actual_mode actual_owner actual_group
    actual_mode="$(stat -c '%a' "${path}")"
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"

    website_health_fail "${path} is ${actual_owner}:${actual_group} ${actual_mode}; expected ${expected_owner}:${expected_group} ${expected_mode}."
    website_hc_offer_directory_fix "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}" "${interactive_fix}"
}

website_hc_report_acl() {
    local path="$1"
    local acl_pattern="$2"
    local description="$3"
    local site_user="$4"
    local is_laravel="$5"
    local interactive_fix="$6"

    if website_hc_acl_matches "${path}" "${acl_pattern}"; then
        website_health_ok "${description}"
        return 0
    fi

    local status=$?
    if [[ "${status}" -eq 2 ]]; then
        website_health_warn "Cannot check ACLs because getfacl is not installed."
        return 0
    fi

    website_health_fail "Missing ACL: ${description}"
    website_hc_offer_acl_repair "${site_user}" "${is_laravel}" "${interactive_fix}"
}

website_hc_report_file_not_world_readable() {
    local path="$1"
    local site_user="$2"
    local interactive_fix="$3"

    [[ -f "${path}" ]] || return 0

    if ! website_hc_file_is_world_readable "${path}"; then
        website_health_ok "${path} is not world-readable."
        return 0
    fi

    local mode owner group
    mode="$(stat -c '%a' "${path}")"
    owner="$(stat -c '%U' "${path}")"
    group="$(stat -c '%G' "${path}")"

    website_health_fail "${path} is ${owner}:${group} ${mode}; it should not be world-readable."
    website_hc_offer_file_fix "${path}" 600 "${site_user}" "${site_user}" ".env often contains secrets, so other local users should not be able to read it." "${interactive_fix}"
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

    user_validate_system_username "${site_user}" || log_fail "Invalid Linux username: ${site_user}"

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
    log_info "Running website health check for ${site_user}."
    if [[ "${interactive_fix}" == "yes" ]]; then
        log_info "Interactive fixes are enabled for low-risk filesystem and ACL issues."
    else
        log_info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
    fi
    echo

    if ! user_system_user_exists "${site_user}"; then
        website_health_fail "Linux site user does not exist: ${site_user}"
        log_info "Website health check complete: ${MH_WEBSITE_HC_PASS_COUNT} passed, ${MH_WEBSITE_HC_WARN_COUNT} warnings, ${MH_WEBSITE_HC_FAIL_COUNT} failures."
        exit 1
    fi
    website_health_ok "Linux site user exists: ${site_user}"

    website_hc_report_directory_owner_mode "${site_home}" 700 "${site_user}" "${site_user}" "The site home should be private to the site user, with Apache granted explicit traversal through ACLs only where needed." "${interactive_fix}"
    website_hc_report_directory_owner_mode "${site_root}" 700 "${site_user}" "${site_user}" "The site root should not rely on group access; Apache gets explicit ACL access to the public document root." "${interactive_fix}"
    website_hc_report_directory_owner_mode "${docroot}" 700 "${site_user}" "${site_user}" "The public document root remains site-owned; Apache receives read access through ACLs rather than ownership or group membership." "${interactive_fix}"
    website_hc_report_directory_owner_mode "${logs}" 700 "${site_user}" "${site_user}" "Logs stay private to the site user; Apache log files are opened by the root Apache parent process and PHP logs are written by PHP-FPM as the site user." "${interactive_fix}"
    website_hc_report_directory_owner_mode "${tmpdir}" 700 "${site_user}" "${site_user}" "Per-site temporary storage is for PHP-FPM running as the site user, not a shared Apache-writable scratch area." "${interactive_fix}"

    if [[ "${is_laravel}" =~ ^[Yy]$ ]]; then
        website_hc_report_directory_owner_mode "${site_root}/storage" 700 "${site_user}" "${site_user}" "Laravel storage must be writable by the PHP-FPM site user; group/world write access is not needed for Apache." "${interactive_fix}"
        website_hc_report_directory_owner_mode "${site_root}/bootstrap/cache" 700 "${site_user}" "${site_user}" "Laravel bootstrap/cache is written by PHP-FPM as the site user during deployment and cache rebuilds." "${interactive_fix}"
        [[ -f "${site_root}/artisan" ]] && website_health_ok "Laravel artisan file exists." || website_health_warn "Laravel artisan file not found; this may be normal before code is deployed."
        [[ -d "${site_root}/public" ]] && website_health_ok "Laravel public directory exists." || website_health_fail "Laravel public directory is missing: ${site_root}/public"
    fi

    website_hc_report_file_not_world_readable "${site_root}/.env" "${site_user}" "${interactive_fix}"

    if command -v getfacl >/dev/null 2>&1; then
        website_hc_report_acl "${site_home}" "^user:${APACHE_RUN_USER}:--x$" "Apache has traversal-only access to ${site_home}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        website_hc_report_acl "${site_root}" "^user:${APACHE_RUN_USER}:--x$" "Apache has traversal-only access to ${site_root}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        website_hc_report_acl "${docroot}" "^user:${APACHE_RUN_USER}:r-x$" "Apache has read/execute access to ${docroot}." "${site_user}" "${is_laravel}" "${interactive_fix}"
        website_hc_report_acl "${docroot}" "^default:user:${APACHE_RUN_USER}:r-x$" "New files under ${docroot} should inherit Apache read/execute ACLs." "${site_user}" "${is_laravel}" "${interactive_fix}"
    fi

    pool_files=()
    for php_version in "${PHP_VERSIONS[@]}"; do
        candidate="/etc/php/${php_version}/fpm/pool.d/${site_user}.conf"
        if [[ -f "${candidate}" ]]; then
            pool_files+=("${candidate}")
        fi
    done

    if [[ "${#pool_files[@]}" -eq 0 ]]; then
        website_health_warn "No PHP-FPM pool found for ${site_user}; this may be normal before vhost creation."
    else
        for pool_file in "${pool_files[@]}"; do
            website_health_ok "PHP-FPM pool exists: ${pool_file}"
            if grep -Eq "^user[[:space:]]*=[[:space:]]*${site_user}$" "${pool_file}"; then
                website_health_ok "${pool_file} runs PHP as ${site_user}."
            else
                website_health_fail "${pool_file} does not appear to run PHP as ${site_user}."
            fi
        done
    fi

    if compgen -G "/etc/apache2/sites-enabled/*${site_user}*" >/dev/null; then
        website_health_ok "An enabled Apache site appears to reference ${site_user}."
    else
        if grep -Rqs "${docroot}" /etc/apache2/sites-enabled 2>/dev/null; then
            website_health_ok "An enabled Apache site points at ${docroot}."
        else
            website_health_warn "No enabled Apache site appears to point at ${docroot}."
        fi
    fi

    echo
    log_info "Website health check complete: ${MH_WEBSITE_HC_PASS_COUNT} passed, ${MH_WEBSITE_HC_WARN_COUNT} warnings, ${MH_WEBSITE_HC_FAIL_COUNT} failures."

    if (( MH_WEBSITE_HC_FAIL_COUNT > 0 )); then
        exit 1
    fi
}

main_website_health_check "$@"
