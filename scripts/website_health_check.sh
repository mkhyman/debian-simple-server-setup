#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

INTERACTIVE_FIX="no"
SITE_USER=""

for arg in "$@"; do
    case "${arg}" in
        --interactive-fix) INTERACTIVE_FIX="yes" ;;
        *) SITE_USER="${arg}" ;;
    esac
done

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

health_ok() { ok "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
health_warn() { warn "$*"; WARN_COUNT=$((WARN_COUNT+1)); }
health_fail() { echo "[FAIL] $*"; echo "[FAIL] $*" >>"${LOG_FILE}"; FAIL_COUNT=$((FAIL_COUNT+1)); }

maybe_fix_dir() {
    local path="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local reason="$5"

    [[ "${INTERACTIVE_FIX}" == "yes" ]] || return 0
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

    [[ "${INTERACTIVE_FIX}" == "yes" ]] || return 0
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

    if [[ ! -d "${path}" ]]; then
        health_fail "Missing directory: ${path}"
        maybe_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}"
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
        maybe_fix_dir "${path}" "${expected_mode}" "${expected_owner}" "${expected_group}" "${reason}"
    fi
}

check_acl_contains() {
    local path="$1"
    local acl_pattern="$2"
    local description="$3"

    if ! command -v getfacl >/dev/null 2>&1; then
        health_warn "Cannot check ACLs because getfacl is not installed."
        return 0
    fi

    if getfacl -cp "${path}" 2>/dev/null | grep -Eq "${acl_pattern}"; then
        health_ok "${description}"
    else
        health_fail "Missing ACL: ${description}"
        if [[ "${INTERACTIVE_FIX}" == "yes" ]]; then
            echo "Apache should receive only the access it needs while PHP runs as the site user."
            if confirm "Re-apply toolkit ACLs for ${SITE_USER}?"; then
                ensure_website_acls "${SITE_USER}" "${IS_LARAVEL}" || health_fail "Could not re-apply website ACLs."
                health_ok "Re-applied website ACLs for ${SITE_USER}."
            fi
        fi
    fi
}

check_file_not_world_readable() {
    local path="$1"

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
        maybe_fix_file_mode_owner "${path}" 600 "${SITE_USER}" "${SITE_USER}" ".env often contains secrets, so other local users should not be able to read it."
    fi
}

if [[ -z "${SITE_USER}" ]]; then
    read -rp "Linux site username to check: " SITE_USER
fi

validate_linux_username "${SITE_USER}" || fail "Invalid Linux username: ${SITE_USER}"

site_home="$(site_home_for_user "${SITE_USER}")"
site_root="$(site_root_for_user "${SITE_USER}")"

if [[ -f "${site_root}/artisan" || -d "${site_root}/bootstrap/cache" || -d "${site_root}/storage" ]]; then
    detected_laravel="Y"
else
    detected_laravel="N"
fi

read -rp "Treat as Laravel site? [${detected_laravel}]: " IS_LARAVEL
IS_LARAVEL="${IS_LARAVEL:-${detected_laravel}}"

docroot="$(site_docroot_for_user "${SITE_USER}" "${IS_LARAVEL}")"
logs="${site_home}/${SITE_LOG_DIR}"
tmpdir="${site_home}/${SITE_TMP_DIR}"

echo
info "Running website health check for ${SITE_USER}."
if [[ "${INTERACTIVE_FIX}" == "yes" ]]; then
    info "Interactive fixes are enabled for low-risk filesystem and ACL issues."
else
    info "Report-only mode. Re-run with --interactive-fix to be prompted for safe repairs."
fi
echo

if ! linux_user_exists "${SITE_USER}"; then
    health_fail "Linux site user does not exist: ${SITE_USER}"
    info "Website health check complete: ${PASS_COUNT} ok, ${WARN_COUNT} warnings, ${FAIL_COUNT} failures."
    exit 1
fi
health_ok "Linux site user exists: ${SITE_USER}"

check_dir "${site_home}" 750 "${SITE_USER}" "${SITE_USER}" "The site home should be private to the site user, with Apache granted access through ACLs only where needed."
check_dir "${site_root}" 750 "${SITE_USER}" "${SITE_USER}" "The site root should be owned by the PHP-FPM site user, not by Apache."
check_dir "${docroot}" 750 "${SITE_USER}" "${SITE_USER}" "Apache should be able to read the public document root through ACLs without owning the whole site."
check_dir "${logs}" 750 "${SITE_USER}" "${SITE_USER}" "Logs live under the site home so they remain grouped with the site and easy to inspect."
check_dir "${tmpdir}" 750 "${SITE_USER}" "${SITE_USER}" "Per-site temporary storage avoids sharing writable runtime paths across sites."

if [[ "${IS_LARAVEL}" =~ ^[Yy]$ ]]; then
    check_dir "${site_root}/storage" 775 "${SITE_USER}" "${SITE_USER}" "Laravel storage must be writable by the PHP-FPM site user for cache, sessions, logs and uploads."
    check_dir "${site_root}/bootstrap/cache" 775 "${SITE_USER}" "${SITE_USER}" "Laravel bootstrap/cache must be writable by the PHP-FPM site user during deployment and cache rebuilds."
    [[ -f "${site_root}/artisan" ]] && health_ok "Laravel artisan file exists." || health_warn "Laravel artisan file not found; this may be normal before code is deployed."
    [[ -d "${site_root}/public" ]] && health_ok "Laravel public directory exists." || health_fail "Laravel public directory is missing: ${site_root}/public"
fi

check_file_not_world_readable "${site_root}/.env"

if command -v getfacl >/dev/null 2>&1; then
    check_acl_contains "${site_home}" "^user:${APACHE_RUN_USER}:--x$" "Apache has traversal-only access to ${site_home}."
    check_acl_contains "${site_root}" "^user:${APACHE_RUN_USER}:--x$" "Apache has traversal-only access to ${site_root}."
    check_acl_contains "${docroot}" "^user:${APACHE_RUN_USER}:r-x$" "Apache has read/execute access to ${docroot}."
    check_acl_contains "${logs}" "^user:${APACHE_RUN_USER}:rwx$" "Apache can write site logs under ${logs}."
    check_acl_contains "${tmpdir}" "^user:${APACHE_RUN_USER}:rwx$" "Apache can use the site's temporary directory."
fi

pool_files=()
for php_version in "${PHP_VERSIONS[@]}"; do
    candidate="/etc/php/${php_version}/fpm/pool.d/${SITE_USER}.conf"
    if [[ -f "${candidate}" ]]; then
        pool_files+=("${candidate}")
    fi
done

if [[ "${#pool_files[@]}" -eq 0 ]]; then
    health_warn "No PHP-FPM pool found for ${SITE_USER}; this may be normal before vhost creation."
else
    for pool_file in "${pool_files[@]}"; do
        health_ok "PHP-FPM pool exists: ${pool_file}"
        if grep -Eq "^user[[:space:]]*=[[:space:]]*${SITE_USER}$" "${pool_file}"; then
            health_ok "${pool_file} runs PHP as ${SITE_USER}."
        else
            health_fail "${pool_file} does not appear to run PHP as ${SITE_USER}."
        fi
    done
fi

if compgen -G "/etc/apache2/sites-enabled/*${SITE_USER}*" >/dev/null; then
    health_ok "An enabled Apache site appears to reference ${SITE_USER}."
else
    if grep -Rqs "${docroot}" /etc/apache2/sites-enabled 2>/dev/null; then
        health_ok "An enabled Apache site points at ${docroot}."
    else
        health_warn "No enabled Apache site appears to point at ${docroot}."
    fi
fi

echo
info "Website health check complete: ${PASS_COUNT} ok, ${WARN_COUNT} warnings, ${FAIL_COUNT} failures."

if (( FAIL_COUNT > 0 )); then
    exit 1
fi
