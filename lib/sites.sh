#!/usr/bin/env bash
###############################################################################
# SITES HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

site_validate_hostname() {
    local host="$1"
    [[ "${host}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "${host}" == *.* ]]
}


site_hostname_to_username() {
    local host="$1"
    echo "${host}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]/_/g; s/_+/_/g; s/^_//; s/_$//'
}


site_home_for_user() {
    local site_user="$1"
    echo "${SITE_BASE_DIR}/${site_user}"
}


site_root_for_user() {
    local site_user="$1"
    echo "$(site_home_for_user "${site_user}")/${SITE_DOC_DIR}"
}


site_docroot_for_user() {
    local site_user="$1"
    local is_laravel="$2"

    if [[ "${is_laravel}" =~ ^[Yy]$ ]]; then
        echo "$(site_root_for_user "${site_user}")/public"
    else
        echo "$(site_root_for_user "${site_user}")"
    fi
}


site_ensure_directories() {
    local site_user="$1"
    local is_laravel="$2"
    local home root docroot

    user_system_user_exists "${site_user}" || return 1

    home="$(site_home_for_user "${site_user}")"
    root="$(site_root_for_user "${site_user}")"
    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"

    # Keep the site's Unix group from becoming an accidental trust boundary.
    # Apache receives explicit ACL access only where required.
    install -d -m 700 -o "${site_user}" -g "${site_user}" "${home}" || return 1
    install -d -m 700 -o "${site_user}" -g "${site_user}" "${root}" || return 1
    install -d -m 700 -o "${site_user}" -g "${site_user}" "${home}/${SITE_LOG_DIR}" || return 1
    install -d -m 700 -o "${site_user}" -g "${site_user}" "${home}/${SITE_TMP_DIR}" || return 1
    install -d -m 700 -o "${site_user}" -g "${site_user}" "${docroot}" || return 1

    if [[ "${is_laravel}" =~ ^[Yy]$ ]]; then
        # PHP-FPM runs as the site user, so Laravel writable paths do not
        # need group/world write bits for Apache.
        install -d -m 700 -o "${site_user}" -g "${site_user}" "${root}/storage" || return 1
        install -d -m 700 -o "${site_user}" -g "${site_user}" "${root}/bootstrap/cache" || return 1
    fi
}


site_ensure_acls() {
    local site_user="$1"
    local is_laravel="$2"
    local home root docroot logs tmpdir

    home="$(site_home_for_user "${site_user}")"
    root="$(site_root_for_user "${site_user}")"
    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"
    logs="${home}/${SITE_LOG_DIR}"
    tmpdir="${home}/${SITE_TMP_DIR}"

    command -v setfacl >/dev/null 2>&1 || return 1

    # Apache only needs to traverse private parent directories and read the
    # public document root. PHP-FPM, running as the site user, handles writable
    # application state.
    setfacl -m "u:${APACHE_RUN_USER}:--x" "${home}" || return 1
    setfacl -m "u:${APACHE_RUN_USER}:--x" "${root}" || return 1
    setfacl -m "u:${APACHE_RUN_USER}:rx" "${docroot}" || return 1
    setfacl -d -m "u:${APACHE_RUN_USER}:rx" "${docroot}" || return 1
}


site_user_is_ready() {
    local site_user="$1"
    local is_laravel="$2"
    local root docroot

    user_system_user_exists "${site_user}" || return 1

    root="$(site_root_for_user "${site_user}")"
    [[ -d "${root}" ]] || return 2

    docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"
    [[ -d "${docroot}" ]] || return 3
}

