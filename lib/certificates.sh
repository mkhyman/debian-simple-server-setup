#!/usr/bin/env bash
###############################################################################
# CERTIFICATES HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

cert_directory_for_name() {
    local cert_name="$1"
    echo "${SERVER_ADMIN_SSL_DIR}/${cert_name}"
}


cert_files_exist() {
    local cert_name="$1"
    local cert_dir

    cert_dir="$(cert_directory_for_name "${cert_name}")"
    [[ -f "${cert_dir}/fullchain.pem" ]] || return 1
    [[ -f "${cert_dir}/privkey.pem" ]] || return 1
}


cert_covers_hostname() {
    local cert_file="$1"
    local hostname="$2"
    local base text

    base="${hostname#*.}"
    text="$(openssl x509 -in "${cert_file}" -noout -text)"

    if echo "${text}" | grep -Eq "DNS:${hostname}([,[:space:]]|$)"; then
        return 0
    fi

    if [[ "${hostname}" == *.* ]] && echo "${text}" | grep -Eq "DNS:\\*\\.${base}([,[:space:]]|$)"; then
        return 0
    fi

    return 1
}

