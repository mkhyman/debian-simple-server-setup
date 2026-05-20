#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

count_begin_certs() { grep -c -- "-----BEGIN CERTIFICATE-----" "$1" || true; }
count_end_certs() { grep -c -- "-----END CERTIFICATE-----" "$1" || true; }

validate_pem_cert_balance() {
    local file="$1"
    local begin_count end_count
    begin_count="$(count_begin_certs "${file}")"
    end_count="$(count_end_certs "${file}")"
    [[ "${begin_count}" -gt 0 ]] || return 1
    [[ "${begin_count}" -eq "${end_count}" ]]
}

choose_file_from_input_dir() {
    local prompt="$1"
    local input_dir="$2"
    local required="$3"
    local value candidate real_input_dir real_candidate

    while true; do
        read -rp "${prompt}: " value

        if [[ -z "${value}" && "${required}" == "no" ]]; then
            echo ""
            return 0
        fi

        [[ -n "${value}" ]] || { warn "This file is required."; continue; }
        [[ "${value}" != /* ]] || { warn "Enter only a filename or relative path inside ${input_dir}."; continue; }

        candidate="${input_dir}/${value}"
        [[ -f "${candidate}" ]] || { warn "File not found: ${candidate}"; continue; }

        real_input_dir="$(realpath "${input_dir}")"
        real_candidate="$(realpath "${candidate}")"

        case "${real_candidate}" in
            "${real_input_dir}"/*) echo "${real_candidate}"; return 0 ;;
            *) warn "File must be inside ${real_input_dir}." ;;
        esac
    done
}

read -rp "Certificate folder/domain, e.g. example.com: " cert_folder
[[ -n "${cert_folder}" ]] || fail "Certificate folder/domain is required."
[[ "${cert_folder}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Invalid certificate folder/domain."

default_input_dir="/home"
read -rp "Input directory containing uploaded cert files [${default_input_dir}]: " input_dir
input_dir="${input_dir:-${default_input_dir}}"
[[ -d "${input_dir}" ]] || fail "Input directory does not exist: ${input_dir}"
input_dir="$(realpath "${input_dir}")"

info "Files found in ${input_dir}:"
find "${input_dir}" -maxdepth 2 -type f -printf '  %P\n' | sort | tee -a "${LOG_FILE}"

private_key_src="$(choose_file_from_input_dir "Private key filename" "${input_dir}" "yes")"
leaf_cert_src="$(choose_file_from_input_dir "Leaf/domain certificate or fullchain filename" "${input_dir}" "yes")"

validate_pem_cert_balance "${leaf_cert_src}" || fail "Invalid certificate PEM balance: ${leaf_cert_src}"

leaf_cert_count="$(count_begin_certs "${leaf_cert_src}")"

if [[ "${leaf_cert_count}" -gt 1 ]]; then
    info "Certificate file contains ${leaf_cert_count} certificates and may already be a fullchain."
    read -rp "Treat this file as a fullchain? [Y/n]: " treat_as_fullchain
    treat_as_fullchain="${treat_as_fullchain:-Y}"
else
    treat_as_fullchain="n"
fi

chain_files=()
temp_extract_dir=""

if [[ ! "${treat_as_fullchain}" =~ ^[Yy]$ ]]; then
    read -rp "Do you have an intermediate/chain ZIP file? [y/N]: " has_chain_zip
    has_chain_zip="${has_chain_zip:-N}"

    if [[ "${has_chain_zip}" =~ ^[Yy]$ ]]; then
        chain_zip_src="$(choose_file_from_input_dir "Intermediate ZIP filename" "${input_dir}" "yes")"
        temp_extract_dir="$(mktemp -d)"
        run unzip -o "${chain_zip_src}" -d "${temp_extract_dir}" || fail "Could not unzip intermediate bundle."

        info "Certificate-like files found inside ZIP:"
        find "${temp_extract_dir}" -type f \( -iname '*.cer' -o -iname '*.crt' -o -iname '*.pem' \) -printf '  %P\n' | sort | tee -a "${LOG_FILE}"

        echo "Enter intermediate certificate filenames from the ZIP in the correct order."
        echo "Leave blank when finished."

        while true; do
            read -rp "Intermediate from ZIP, blank to finish: " zip_chain_rel
            [[ -z "${zip_chain_rel}" ]] && break
            zip_chain_file="${temp_extract_dir}/${zip_chain_rel}"
            [[ -f "${zip_chain_file}" ]] || { warn "Not found: ${zip_chain_file}"; continue; }
            validate_pem_cert_balance "${zip_chain_file}" || { warn "Invalid PEM balance: ${zip_chain_file}"; continue; }
            chain_files+=("$(realpath "${zip_chain_file}")")
        done
    fi

    read -rp "Add loose intermediate certificate files from input directory too? [y/N]: " has_loose_chain
    has_loose_chain="${has_loose_chain:-N}"

    if [[ "${has_loose_chain}" =~ ^[Yy]$ ]]; then
        while true; do
            loose_chain_file="$(choose_file_from_input_dir "Intermediate filename, blank to finish" "${input_dir}" "no")"
            [[ -z "${loose_chain_file}" ]] && break
            validate_pem_cert_balance "${loose_chain_file}" || { warn "Invalid PEM balance: ${loose_chain_file}"; continue; }
            chain_files+=("${loose_chain_file}")
        done
    fi
fi

dest_dir="$(certificate_dir_for_name "${cert_folder}")"
install -d -m 700 -o root -g root "${SERVER_ADMIN_SSL_DIR}"
install -d -m 700 -o root -g root "${dest_dir}"

cert_dst="${dest_dir}/cert.pem"
key_dst="${dest_dir}/privkey.pem"
chain_dst="${dest_dir}/chain.pem"
fullchain_dst="${dest_dir}/fullchain.pem"
source_notes="${dest_dir}/source-files.txt"

backup_file "${cert_dst}" || fail "Could not back up cert.pem."
backup_file "${key_dst}" || fail "Could not back up privkey.pem."
backup_file "${chain_dst}" || fail "Could not back up chain.pem."
backup_file "${fullchain_dst}" || fail "Could not back up fullchain.pem."
backup_file "${source_notes}" || fail "Could not back up source-files.txt."

cp -a "${private_key_src}" "${key_dst}"

if [[ "${treat_as_fullchain}" =~ ^[Yy]$ ]]; then
    cp -a "${leaf_cert_src}" "${fullchain_dst}"
    awk '/-----BEGIN CERTIFICATE-----/ { n++ } n == 1 { print } /-----END CERTIFICATE-----/ && n == 1 { exit }' "${leaf_cert_src}" > "${cert_dst}"
    awk '/-----BEGIN CERTIFICATE-----/ { n++ } n >= 2 { print }' "${leaf_cert_src}" > "${chain_dst}"
    [[ -s "${chain_dst}" ]] || rm -f "${chain_dst}"
else
    cp -a "${leaf_cert_src}" "${cert_dst}"
    : > "${chain_dst}"
    for chain_file in "${chain_files[@]}"; do
        cat "${chain_file}" >> "${chain_dst}"
        printf '\n' >> "${chain_dst}"
    done

    if [[ -s "${chain_dst}" ]]; then
        cat "${cert_dst}" "${chain_dst}" > "${fullchain_dst}"
    else
        cp -a "${cert_dst}" "${fullchain_dst}"
    fi
fi

chown root:root "${dest_dir}"/*
chmod 600 "${key_dst}"
chmod 644 "${cert_dst}" "${fullchain_dst}"
[[ -f "${chain_dst}" ]] && chmod 644 "${chain_dst}"

validate_pem_cert_balance "${cert_dst}" || fail "Invalid cert.pem."
validate_pem_cert_balance "${fullchain_dst}" || fail "Invalid fullchain.pem."
[[ -f "${chain_dst}" ]] && validate_pem_cert_balance "${chain_dst}" || true

cert_pub_hash="$(openssl x509 -in "${cert_dst}" -pubkey -noout | openssl pkey -pubin -outform DER | openssl sha256)"
key_pub_hash="$(openssl pkey -in "${key_dst}" -pubout -outform DER | openssl sha256)"
[[ "${cert_pub_hash}" == "${key_pub_hash}" ]] || fail "Private key does not match certificate."

{
    echo "Certificate folder/domain: ${cert_folder}"
    echo "Imported at: $(date -Is)"
    echo "Input directory: ${input_dir}"
    echo "Private key source: ${private_key_src}"
    echo "Leaf/fullchain source: ${leaf_cert_src}"
    echo "Treated supplied cert as fullchain: ${treat_as_fullchain}"
    echo "Intermediate files:"
    for chain_file in "${chain_files[@]:-}"; do
        echo "  - ${chain_file}"
    done
} > "${source_notes}"

chmod 600 "${source_notes}"
chown root:root "${source_notes}"

[[ -n "${temp_extract_dir}" && -d "${temp_extract_dir}" ]] && rm -rf "${temp_extract_dir}"

ok "Certificate import complete: ${dest_dir}"
