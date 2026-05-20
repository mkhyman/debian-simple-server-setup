#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# IMPORT PAID SSL CERTIFICATE
#
# Normalises paid certificate provider output into the authoritative certificate
# directory under /server-admin/ssl-certificates.
#
# This script does not create self-signed/snakeoil website certificates.
###############################################################################

count_begin_certs() {
    grep -c -- "-----BEGIN CERTIFICATE-----" "$1" || true
}

count_end_certs() {
    grep -c -- "-----END CERTIFICATE-----" "$1" || true
}

validate_pem_cert_balance() {
    local file="$1"
    local begin_count end_count

    begin_count="$(count_begin_certs "${file}")"
    end_count="$(count_end_certs "${file}")"

    [[ "${begin_count}" -gt 0 ]] || fail "No PEM certificates found in ${file}."
    [[ "${begin_count}" -eq "${end_count}" ]] || fail "BEGIN/END certificate mismatch in ${file}."
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

        if [[ -z "${value}" ]]; then
            warn "This file is required."
            continue
        fi

        if [[ "${value}" = /* ]]; then
            warn "Enter only a filename or relative path inside ${input_dir}."
            continue
        fi

        candidate="${input_dir}/${value}"

        if [[ ! -f "${candidate}" ]]; then
            warn "File not found: ${candidate}"
            continue
        fi

        real_input_dir="$(realpath "${input_dir}")"
        real_candidate="$(realpath "${candidate}")"

        case "${real_candidate}" in
            "${real_input_dir}"/*)
                echo "${real_candidate}"
                return 0
                ;;
            *)
                warn "File must be inside ${real_input_dir}."
                ;;
        esac
    done
}

read -rp "Certificate folder/domain, e.g. example.com: " CERT_FOLDER
[[ -n "${CERT_FOLDER}" ]] || fail "Certificate folder/domain is required."

if [[ ! "${CERT_FOLDER}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "Invalid certificate folder/domain: ${CERT_FOLDER}"
fi

DEFAULT_INPUT_DIR="/home/${ADMIN_USER}/cert-upload"
read -rp "Input directory containing uploaded cert files [${DEFAULT_INPUT_DIR}]: " INPUT_DIR
INPUT_DIR="${INPUT_DIR:-${DEFAULT_INPUT_DIR}}"

[[ -d "${INPUT_DIR}" ]] || fail "Input directory does not exist: ${INPUT_DIR}"
INPUT_DIR="$(realpath "${INPUT_DIR}")"

info "Files found in ${INPUT_DIR}:"
find "${INPUT_DIR}" -maxdepth 2 -type f -printf '  %P\n' | sort | tee -a "${LOG_FILE}"

PRIVATE_KEY_SRC="$(choose_file_from_input_dir "Private key filename" "${INPUT_DIR}" "yes")"
LEAF_CERT_SRC="$(choose_file_from_input_dir "Leaf/domain certificate or fullchain filename" "${INPUT_DIR}" "yes")"

validate_pem_cert_balance "${LEAF_CERT_SRC}"
LEAF_CERT_COUNT="$(count_begin_certs "${LEAF_CERT_SRC}")"

if [[ "${LEAF_CERT_COUNT}" -gt 1 ]]; then
    info "Certificate file contains ${LEAF_CERT_COUNT} certificates and may already be a fullchain."
    read -rp "Treat this file as a fullchain? [Y/n]: " TREAT_AS_FULLCHAIN
    TREAT_AS_FULLCHAIN="${TREAT_AS_FULLCHAIN:-Y}"
else
    TREAT_AS_FULLCHAIN="n"
fi

CHAIN_FILES=()
TEMP_EXTRACT_DIR=""

if [[ ! "${TREAT_AS_FULLCHAIN}" =~ ^[Yy]$ ]]; then
    read -rp "Do you have an intermediate/chain ZIP file? [y/N]: " HAS_CHAIN_ZIP
    HAS_CHAIN_ZIP="${HAS_CHAIN_ZIP:-N}"

    if [[ "${HAS_CHAIN_ZIP}" =~ ^[Yy]$ ]]; then
        CHAIN_ZIP_SRC="$(choose_file_from_input_dir "Intermediate ZIP filename" "${INPUT_DIR}" "yes")"
        TEMP_EXTRACT_DIR="$(mktemp -d)"

        info "Extracting intermediate ZIP."
        run unzip -o "${CHAIN_ZIP_SRC}" -d "${TEMP_EXTRACT_DIR}"

        info "Certificate-like files found inside ZIP:"
        find "${TEMP_EXTRACT_DIR}" -type f \( -iname '*.cer' -o -iname '*.crt' -o -iname '*.pem' \) -printf '  %P\n' | sort | tee -a "${LOG_FILE}"

        echo "Enter intermediate certificate filenames from the ZIP in the correct order."
        echo "Leave blank when finished."

        while true; do
            read -rp "Intermediate from ZIP, blank to finish: " ZIP_CHAIN_REL
            [[ -z "${ZIP_CHAIN_REL}" ]] && break

            ZIP_CHAIN_FILE="${TEMP_EXTRACT_DIR}/${ZIP_CHAIN_REL}"

            if [[ ! -f "${ZIP_CHAIN_FILE}" ]]; then
                warn "Not found: ${ZIP_CHAIN_FILE}"
                continue
            fi

            validate_pem_cert_balance "${ZIP_CHAIN_FILE}"
            CHAIN_FILES+=("$(realpath "${ZIP_CHAIN_FILE}")")
        done
    fi

    read -rp "Add loose intermediate certificate files from input directory too? [y/N]: " HAS_LOOSE_CHAIN
    HAS_LOOSE_CHAIN="${HAS_LOOSE_CHAIN:-N}"

    if [[ "${HAS_LOOSE_CHAIN}" =~ ^[Yy]$ ]]; then
        echo "Enter intermediate filenames relative to ${INPUT_DIR}. Leave blank when finished."

        while true; do
            LOOSE_CHAIN_FILE="$(choose_file_from_input_dir "Intermediate filename, blank to finish" "${INPUT_DIR}" "no")"
            [[ -z "${LOOSE_CHAIN_FILE}" ]] && break

            validate_pem_cert_balance "${LOOSE_CHAIN_FILE}"
            CHAIN_FILES+=("${LOOSE_CHAIN_FILE}")
        done
    fi
fi

DEST_DIR="${SERVER_ADMIN_SSL_DIR}/${CERT_FOLDER}"
install -d -m 700 -o root -g root "${SERVER_ADMIN_SSL_DIR}"
install -d -m 700 -o root -g root "${DEST_DIR}"

CERT_DST="${DEST_DIR}/cert.pem"
KEY_DST="${DEST_DIR}/privkey.pem"
CHAIN_DST="${DEST_DIR}/chain.pem"
FULLCHAIN_DST="${DEST_DIR}/fullchain.pem"
SOURCE_NOTES="${DEST_DIR}/source-files.txt"

backup_file "${CERT_DST}"
backup_file "${KEY_DST}"
backup_file "${CHAIN_DST}"
backup_file "${FULLCHAIN_DST}"
backup_file "${SOURCE_NOTES}"

cp -a "${PRIVATE_KEY_SRC}" "${KEY_DST}"

if [[ "${TREAT_AS_FULLCHAIN}" =~ ^[Yy]$ ]]; then
    cp -a "${LEAF_CERT_SRC}" "${FULLCHAIN_DST}"

    # Extract the first cert as the leaf cert, and the rest as chain.pem.
    awk '/-----BEGIN CERTIFICATE-----/ { n++ } n == 1 { print } /-----END CERTIFICATE-----/ && n == 1 { exit }' "${LEAF_CERT_SRC}" > "${CERT_DST}"
    awk '/-----BEGIN CERTIFICATE-----/ { n++ } n >= 2 { print }' "${LEAF_CERT_SRC}" > "${CHAIN_DST}"

    [[ -s "${CHAIN_DST}" ]] || rm -f "${CHAIN_DST}"
else
    cp -a "${LEAF_CERT_SRC}" "${CERT_DST}"

    : > "${CHAIN_DST}"
    for chain_file in "${CHAIN_FILES[@]}"; do
        cat "${chain_file}" >> "${CHAIN_DST}"
        printf '\n' >> "${CHAIN_DST}"
    done

    if [[ -s "${CHAIN_DST}" ]]; then
        cat "${CERT_DST}" "${CHAIN_DST}" > "${FULLCHAIN_DST}"
    else
        cp -a "${CERT_DST}" "${FULLCHAIN_DST}"
    fi
fi

chown root:root "${DEST_DIR}"/*
chmod 600 "${KEY_DST}"
chmod 644 "${CERT_DST}" "${FULLCHAIN_DST}"
[[ -f "${CHAIN_DST}" ]] && chmod 644 "${CHAIN_DST}"

validate_pem_cert_balance "${CERT_DST}"
validate_pem_cert_balance "${FULLCHAIN_DST}"
[[ -f "${CHAIN_DST}" ]] && validate_pem_cert_balance "${CHAIN_DST}"

info "Checking private key matches certificate."
CERT_PUB_HASH="$(openssl x509 -in "${CERT_DST}" -pubkey -noout | openssl pkey -pubin -outform DER | openssl sha256)"
KEY_PUB_HASH="$(openssl pkey -in "${KEY_DST}" -pubout -outform DER | openssl sha256)"

[[ "${CERT_PUB_HASH}" == "${KEY_PUB_HASH}" ]] || fail "Private key does not match certificate."
ok "Private key matches certificate."

info "Certificate summary:"
openssl x509 -in "${CERT_DST}" -noout -subject -issuer -dates | tee -a "${LOG_FILE}"

FULLCHAIN_COUNT="$(count_begin_certs "${FULLCHAIN_DST}")"
info "fullchain.pem contains ${FULLCHAIN_COUNT} certificate(s)."

if [[ "${FULLCHAIN_COUNT}" -lt 2 ]]; then
    warn "fullchain.pem contains only one certificate. Most paid certs require at least one intermediate."
fi

{
    echo "Certificate folder/domain: ${CERT_FOLDER}"
    echo "Imported at: $(date -Is)"
    echo "Input directory: ${INPUT_DIR}"
    echo "Private key source: ${PRIVATE_KEY_SRC}"
    echo "Leaf/fullchain source: ${LEAF_CERT_SRC}"
    echo "Treated supplied cert as fullchain: ${TREAT_AS_FULLCHAIN}"
    echo "Intermediate files:"
    for chain_file in "${CHAIN_FILES[@]:-}"; do
        echo "  - ${chain_file}"
    done
} > "${SOURCE_NOTES}"

chmod 600 "${SOURCE_NOTES}"
chown root:root "${SOURCE_NOTES}"

if [[ -n "${TEMP_EXTRACT_DIR}" && -d "${TEMP_EXTRACT_DIR}" ]]; then
    rm -rf "${TEMP_EXTRACT_DIR}"
fi

ok "Certificate import complete: ${DEST_DIR}"
info "For Apache use:"
info "  SSLCertificateFile ${FULLCHAIN_DST}"
info "  SSLCertificateKeyFile ${KEY_DST}"
