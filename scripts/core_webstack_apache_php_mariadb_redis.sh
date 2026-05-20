#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

export DEBIAN_FRONTEND=noninteractive

info "Installing Apache, MariaDB, Redis and base tooling."
run apt-get update || fail "apt-get update failed."
run apt-get install -y apache2 mariadb-server redis-server curl wget ca-certificates \
    lsb-release apt-transport-https gnupg openssl unzip || fail "Web stack base package install failed."

# Sury is used because personal hosting sometimes needs legacy PHP beside the
# current default; co-installable versions keep old sites contained.
info "Configuring Sury PHP repository for co-installable PHP versions including PHP 7.4."
if [[ ! -f "${SURY_KEYRING}" ]]; then
    run bash -c "curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o '${SURY_KEYRING}'" || fail "Could not install Sury keyring."
fi

codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [signed-by=${SURY_KEYRING}] https://packages.sury.org/php/ ${codename} main" > "${SURY_LIST}"
run apt-get update || fail "apt-get update failed after adding Sury repository."

for php_version in "${PHP_VERSIONS[@]}"; do
    info "Installing PHP ${php_version} with Laravel-friendly extensions."
    run apt-get install -y \
        "php${php_version}-cli" "php${php_version}-fpm" "php${php_version}-common" \
        "php${php_version}-mysql" "php${php_version}-mbstring" "php${php_version}-xml" \
        "php${php_version}-curl" "php${php_version}-zip" "php${php_version}-bcmath" \
        "php${php_version}-intl" "php${php_version}-gd" "php${php_version}-readline" \
        "php${php_version}-opcache" "php${php_version}-redis" || fail "Could not install PHP ${php_version}."
    service_enable_now "php${php_version}-fpm" || fail "Could not enable PHP-FPM ${php_version}."
done

if command -v "php${DEFAULT_PHP_VERSION}" >/dev/null 2>&1; then
    run update-alternatives --set php "/usr/bin/php${DEFAULT_PHP_VERSION}" || warn "Could not set default CLI PHP."
fi

# Apache is kept as the stable front door; PHP runs through FPM so each site can
# have its own pool and user rather than sharing mod_php process state.
info "Enabling Apache modules."
run a2enmod rewrite headers ssl proxy_fcgi setenvif http2 expires deflate proxy proxy_http remoteip || fail "Could not enable Apache modules."
a2dismod php8.4 php7.4 >>"${LOG_FILE}" 2>&1 || true

# Validate before restart because Apache is shared infrastructure: one broken
# module/vhost should not take every personal site offline.
service_enable_now apache2 || fail "Could not enable Apache."
restart_apache_safely || fail "Could not validate and restart Apache."

# MariaDB is allowed to listen remotely, so TLS is configured as part of the
# service baseline rather than relying on every database user to remember it.
info "Preparing MariaDB TLS files."
install -d -m 750 -o mysql -g mysql "${MARIADB_SSL_DIR}"

if [[ ! -f "${MARIADB_CA_CERT}" ]]; then
    run bash -c "openssl genrsa 4096 > '${MARIADB_CA_KEY}'" || fail "Could not generate MariaDB CA key."
    run openssl req -new -x509 -nodes -days 3650 \
        -key "${MARIADB_CA_KEY}" \
        -out "${MARIADB_CA_CERT}" \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)-MariaDB-CA" || fail "Could not generate MariaDB CA certificate."
fi

if [[ ! -f "${MARIADB_SERVER_CERT}" ]]; then
    run openssl req -newkey rsa:4096 -days 3650 -nodes \
        -keyout "${MARIADB_SERVER_KEY}" \
        -out "${MARIADB_SERVER_CSR}" \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)" || fail "Could not generate MariaDB server CSR."
    run openssl x509 -req -in "${MARIADB_SERVER_CSR}" \
        -days 3650 \
        -CA "${MARIADB_CA_CERT}" \
        -CAkey "${MARIADB_CA_KEY}" \
        -set_serial 01 \
        -out "${MARIADB_SERVER_CERT}" || fail "Could not sign MariaDB server certificate."
fi

run chown -R mysql:mysql "${MARIADB_SSL_DIR}" || fail "Could not chown MariaDB SSL dir."
run chmod 600 "${MARIADB_CA_KEY}" "${MARIADB_SERVER_KEY}" || fail "Could not chmod MariaDB private keys."
run chmod 644 "${MARIADB_CA_CERT}" "${MARIADB_SERVER_CERT}" || fail "Could not chmod MariaDB certs."

tmp_mariadb="$(mktemp)"
cat >"${tmp_mariadb}" <<EOF
$(managed_header "core_webstack_apache_php_mariadb_redis.sh")
[mariadb]
bind-address = 0.0.0.0
port = ${MARIADB_PORT}
require_secure_transport = ON
ssl-ca = ${MARIADB_CA_CERT}
ssl-cert = ${MARIADB_SERVER_CERT}
ssl-key = ${MARIADB_SERVER_KEY}
EOF

write_managed_file "${MARIADB_REMOTE_SSL_CONFIG}" 0644 root:root "${tmp_mariadb}" || fail "Could not write MariaDB TLS config."

# MariaDB config is validated before restart for the same reason as Apache: a
# bad generated snippet should fail safely before the daemon is disrupted.
service_enable_now mariadb || fail "Could not enable MariaDB."
restart_mariadb_safely || fail "Could not validate and restart MariaDB."

# Redis is kept local-only because Laravel typically uses it as an application
# dependency, not as a public network service.
info "Configuring Redis as local-only."
backup_file /etc/redis/redis.conf || fail "Could not back up redis.conf."
sed -i -E "s/^bind .*/bind ${REDIS_BIND}/" /etc/redis/redis.conf
sed -i -E "s/^protected-mode .*/protected-mode yes/" /etc/redis/redis.conf

service_enable_now redis-server || fail "Could not enable Redis."
restart_redis_safely || fail "Could not restart Redis."

cat >"${SERVER_ADMIN_MARIADB_DIR}/README.txt" <<EOF
MariaDB TLS notes
=================

Authoritative MariaDB TLS files live in:

  ${MARIADB_SSL_DIR}

MariaDB TLS config:
  ${MARIADB_REMOTE_SSL_CONFIG}

Remote users should be created with REQUIRE SSL.
REQUIRE X509 is intentionally not used at this stage.
EOF

ok "Web stack installed."
