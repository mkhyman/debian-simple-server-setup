#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# WEB STACK
#
# Installs Apache, PHP-FPM versions, MariaDB with TLS-required remote access,
# and Redis local-only. PHP 7.4 comes from Sury because it is legacy/EOL and not
# expected from normal Debian 13 repositories.
###############################################################################

export DEBIAN_FRONTEND=noninteractive

info "Installing Apache, MariaDB, Redis and base tooling."
run apt-get update
run apt-get install -y \
    apache2 \
    mariadb-server \
    redis-server \
    curl \
    wget \
    ca-certificates \
    lsb-release \
    apt-transport-https \
    gnupg \
    openssl \
    unzip

info "Configuring Sury PHP repository for co-installable PHP versions including legacy PHP 7.4."
if [[ ! -f "${SURY_KEYRING}" ]]; then
    run bash -c "curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o '${SURY_KEYRING}'"
else
    info "Sury keyring already exists: ${SURY_KEYRING}"
fi

CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [signed-by=${SURY_KEYRING}] https://packages.sury.org/php/ ${CODENAME} main" > "${SURY_LIST}"
run apt-get update

for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    info "Installing PHP ${PHP_VERSION} with Laravel-friendly extensions."
    run apt-get install -y \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-readline" \
        "php${PHP_VERSION}-opcache" \
        "php${PHP_VERSION}-redis"

    run systemctl enable --now "php${PHP_VERSION}-fpm"
done

if command -v "php${DEFAULT_PHP_VERSION}" >/dev/null 2>&1; then
    info "Setting default CLI PHP to ${DEFAULT_PHP_VERSION} for admin convenience."
    run update-alternatives --set php "/usr/bin/php${DEFAULT_PHP_VERSION}"
else
    warn "php${DEFAULT_PHP_VERSION} command not found; skipping CLI default PHP update."
fi

info "Enabling Apache modules required for HTTPS, PHP-FPM, Laravel rewrites and headers."
run a2enmod rewrite headers ssl proxy_fcgi setenvif http2 expires deflate proxy proxy_http remoteip

# mod_php is deliberately disabled because the agreed hosting model is Apache +
# PHP-FPM, with isolated per-site pools.
a2dismod php8.4 php7.4 >>"${LOG_FILE}" 2>&1 || true

run systemctl enable --now apache2
run systemctl restart apache2

info "Preparing MariaDB TLS files."
install -d -m 750 -o mysql -g mysql "${MARIADB_SSL_DIR}"

if [[ ! -f "${MARIADB_CA_CERT}" ]]; then
    info "Generating local MariaDB CA certificate."
    run bash -c "openssl genrsa 4096 > '${MARIADB_CA_KEY}'"
    run openssl req -new -x509 -nodes -days 3650 \
        -key "${MARIADB_CA_KEY}" \
        -out "${MARIADB_CA_CERT}" \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)-MariaDB-CA"
else
    info "MariaDB CA certificate already exists."
fi

if [[ ! -f "${MARIADB_SERVER_CERT}" ]]; then
    info "Generating MariaDB server certificate."
    run openssl req -newkey rsa:4096 -days 3650 -nodes \
        -keyout "${MARIADB_SERVER_KEY}" \
        -out "${MARIADB_SERVER_CSR}" \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)"

    run openssl x509 -req -in "${MARIADB_SERVER_CSR}" \
        -days 3650 \
        -CA "${MARIADB_CA_CERT}" \
        -CAkey "${MARIADB_CA_KEY}" \
        -set_serial 01 \
        -out "${MARIADB_SERVER_CERT}"
else
    info "MariaDB server certificate already exists."
fi

run chown -R mysql:mysql "${MARIADB_SSL_DIR}"
run chmod 600 "${MARIADB_CA_KEY}" "${MARIADB_SERVER_KEY}"
run chmod 644 "${MARIADB_CA_CERT}" "${MARIADB_SERVER_CERT}"

info "Configuring MariaDB for remote access with encrypted transport required."
backup_file "${MARIADB_REMOTE_SSL_CONFIG}"

tmp_mariadb="$(mktemp)"
cat >"${tmp_mariadb}" <<EOF
$(managed_header "03_core_webstack_apache_php_mariadb_redis.sh")
[mariadb]
bind-address = 0.0.0.0
port = ${MARIADB_PORT}
require_secure_transport = ON
ssl-ca = ${MARIADB_CA_CERT}
ssl-cert = ${MARIADB_SERVER_CERT}
ssl-key = ${MARIADB_SERVER_KEY}
EOF

write_managed_file "${MARIADB_REMOTE_SSL_CONFIG}" 0644 root:root "${tmp_mariadb}"

run systemctl enable --now mariadb
run systemctl restart mariadb

info "Configuring Redis as local-only."
info "Laravel may use Redis for cache/queues, but Redis should not be internet-facing."
backup_file /etc/redis/redis.conf

if grep -qE '^bind ' /etc/redis/redis.conf; then
    sed -i -E "s/^bind .*/bind ${REDIS_BIND}/" /etc/redis/redis.conf
else
    echo "bind ${REDIS_BIND}" >> /etc/redis/redis.conf
fi

if grep -qE '^protected-mode ' /etc/redis/redis.conf; then
    sed -i -E "s/^protected-mode .*/protected-mode yes/" /etc/redis/redis.conf
else
    echo "protected-mode yes" >> /etc/redis/redis.conf
fi

run systemctl enable --now redis-server
run systemctl restart redis-server

info "Writing MariaDB README. This is documentation only, not a duplicate cert store."
cat >"${SERVER_ADMIN_MARIADB_DIR}/README.txt" <<EOF
MariaDB TLS notes
=================

Authoritative MariaDB TLS files live in:

  ${MARIADB_SSL_DIR}

Do not maintain duplicate copies in:

  ${SERVER_ADMIN_MARIADB_DIR}

Important files:

  CA certificate:
    ${MARIADB_CA_CERT}

  Server certificate:
    ${MARIADB_SERVER_CERT}

  Server private key:
    ${MARIADB_SERVER_KEY}

MariaDB TLS config:
  ${MARIADB_REMOTE_SSL_CONFIG}

Remote users should be created with:
  REQUIRE SSL

REQUIRE X509 is intentionally not used at this stage.
EOF

ok "Web stack installed."
info "MariaDB CA certificate for remote clients: ${MARIADB_CA_CERT}"
