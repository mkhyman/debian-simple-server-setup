#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# CREATE HTTPS-ONLY APACHE VHOST
#
# Creates an isolated PHP-FPM pool for the site user, an HTTP redirect vhost,
# and an HTTPS vhost using paid certificate files from server-admin.
###############################################################################

read -rp "Primary hostname / ServerName, e.g. shop.example.com: " HOSTNAME
validate_hostname "${HOSTNAME}"

DEFAULT_SITE_USER="$(hostname_to_username "${HOSTNAME}")"
read -rp "Linux site username [${DEFAULT_SITE_USER}]: " SITE_USER
SITE_USER="${SITE_USER:-${DEFAULT_SITE_USER}}"

read -rp "Extra hostnames / ServerAlias, space-separated or blank: " SERVER_ALIASES

read -rp "PHP version [${DEFAULT_PHP_VERSION}]: " PHP_VERSION
PHP_VERSION="${PHP_VERSION:-${DEFAULT_PHP_VERSION}}"

read -rp "Laravel site? [Y/n]: " IS_LARAVEL
IS_LARAVEL="${IS_LARAVEL:-Y}"

if ! id "${SITE_USER}" &>/dev/null; then
    fail "User ${SITE_USER} does not exist. Run site_create_website_user.sh first."
fi

if [[ ! -d "/etc/php/${PHP_VERSION}/fpm" ]]; then
    fail "PHP-FPM ${PHP_VERSION} is not installed."
fi

SITE_HOME="${SITE_BASE_DIR}/${SITE_USER}"
SITE_ROOT="${SITE_HOME}/${SITE_DOC_DIR}"

if [[ "${IS_LARAVEL}" =~ ^[Yy]$ ]]; then
    DOCROOT="${SITE_ROOT}/public"
else
    DOCROOT="${SITE_ROOT}"
fi

install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${DOCROOT}"
install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}/${SITE_LOG_DIR}"
install -d -m 750 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_HOME}/${SITE_TMP_DIR}"

echo
echo "SSL certificate options:"
echo "  1) Use existing certificate"
echo "  2) Import new paid certificate"
read -rp "Choice [1]: " CERT_CHOICE
CERT_CHOICE="${CERT_CHOICE:-1}"

if [[ "${CERT_CHOICE}" == "2" ]]; then
    "${SCRIPT_DIR}/site_import_paid_certificate.sh"
elif [[ "${CERT_CHOICE}" != "1" ]]; then
    fail "Invalid certificate choice: ${CERT_CHOICE}"
fi

DEFAULT_CERT_FOLDER="${HOSTNAME#*.}"
read -rp "Certificate folder/domain [${DEFAULT_CERT_FOLDER}]: " CERT_FOLDER
CERT_FOLDER="${CERT_FOLDER:-${DEFAULT_CERT_FOLDER}}"

CERT_DIR="${SERVER_ADMIN_SSL_DIR}/${CERT_FOLDER}"
FULLCHAIN="${CERT_DIR}/fullchain.pem"
PRIVKEY="${CERT_DIR}/privkey.pem"

[[ -f "${FULLCHAIN}" ]] || fail "Missing fullchain: ${FULLCHAIN}"
[[ -f "${PRIVKEY}" ]] || fail "Missing private key: ${PRIVKEY}"

if check_cert_covers_hostname "${FULLCHAIN}" "${HOSTNAME}"; then
    ok "Certificate appears to cover ${HOSTNAME}."
else
    warn "Certificate may not cover ${HOSTNAME}."
    warn "This may be fine only if the SAN parser missed something unusual."
    confirm "Continue anyway?" || exit 1
fi

POOL_FILE="/etc/php/${PHP_VERSION}/fpm/pool.d/${SITE_USER}.conf"
SOCKET="/run/php/php${PHP_VERSION}-fpm-${SITE_USER}.sock"

tmp_pool="$(mktemp)"
cat >"${tmp_pool}" <<EOF
$(managed_header "site_create_https_vhost.sh")
[${SITE_USER}]
user = ${SITE_USER}
group = ${SITE_USER}

listen = ${SOCKET}
listen.owner = ${APACHE_RUN_USER}
listen.group = ${APACHE_RUN_GROUP}
listen.mode = 0660

pm = ondemand
pm.max_children = 10
pm.process_idle_timeout = 10s
pm.max_requests = 500

php_admin_value[open_basedir] = ${SITE_HOME}:/tmp
php_admin_value[upload_tmp_dir] = ${SITE_HOME}/${SITE_TMP_DIR}
php_admin_value[session.save_path] = ${SITE_HOME}/${SITE_TMP_DIR}
php_admin_value[error_log] = ${SITE_HOME}/${SITE_LOG_DIR}/php-error.log
php_admin_flag[log_errors] = on

catch_workers_output = yes
EOF

write_managed_file "${POOL_FILE}" 0644 root:root "${tmp_pool}"

SERVER_ALIAS_LINE=""
if [[ -n "${SERVER_ALIASES}" ]]; then
    SERVER_ALIAS_LINE="    ServerAlias ${SERVER_ALIASES}"
fi

HTTP_VHOST="/etc/apache2/sites-available/${HOSTNAME}.conf"
HTTPS_VHOST="/etc/apache2/sites-available/${HOSTNAME}-ssl.conf"

tmp_http="$(mktemp)"
cat >"${tmp_http}" <<EOF
$(managed_header "site_create_https_vhost.sh")
<VirtualHost *:80>
    ServerName ${HOSTNAME}
${SERVER_ALIAS_LINE}

    ErrorLog ${SITE_HOME}/${SITE_LOG_DIR}/${HOSTNAME}-http-error.log
    CustomLog ${SITE_HOME}/${SITE_LOG_DIR}/${HOSTNAME}-http-access.log combined

    Redirect permanent / https://${HOSTNAME}/
</VirtualHost>
EOF

tmp_https="$(mktemp)"
cat >"${tmp_https}" <<EOF
$(managed_header "site_create_https_vhost.sh")
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName ${HOSTNAME}
${SERVER_ALIAS_LINE}

    DocumentRoot ${DOCROOT}

    ErrorLog ${SITE_HOME}/${SITE_LOG_DIR}/${HOSTNAME}-ssl-error.log
    CustomLog ${SITE_HOME}/${SITE_LOG_DIR}/${HOSTNAME}-ssl-access.log combined

    SSLEngine on
    SSLCertificateFile ${FULLCHAIN}
    SSLCertificateKeyFile ${PRIVKEY}

    Protocols h2 http/1.1

    <Directory ${DOCROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:${SOCKET}|fcgi://localhost/"
    </FilesMatch>

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # HSTS is deliberately not enabled by default.
    # Enable only once you are certain all relevant subdomains have working HTTPS.
    # Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>
</IfModule>
EOF

write_managed_file "${HTTP_VHOST}" 0644 root:root "${tmp_http}"
write_managed_file "${HTTPS_VHOST}" 0644 root:root "${tmp_https}"

if [[ "${IS_LARAVEL}" =~ ^[Yy]$ ]]; then
    install -d -m 775 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_ROOT}/storage"
    install -d -m 775 -o "${SITE_USER}" -g "${SITE_USER}" "${SITE_ROOT}/bootstrap/cache"
fi

chown -R "${SITE_USER}:${SITE_USER}" "${SITE_HOME}"

run a2ensite "${HOSTNAME}.conf"
run a2ensite "${HOSTNAME}-ssl.conf"
run apache2ctl configtest
run systemctl restart "php${PHP_VERSION}-fpm"
run systemctl reload apache2

ok "HTTPS site created for ${HOSTNAME} using PHP ${PHP_VERSION}."
info "DocumentRoot: ${DOCROOT}"
