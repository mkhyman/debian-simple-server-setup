#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

export DEBIAN_FRONTEND=noninteractive

log_info "Installing Apache, MariaDB, Redis and base tooling."
log_run apt-get update || log_fail "apt-get update failed. Web stack package installation was not attempted."
log_run apt-get install -y apache2 mariadb-server redis-server curl wget ca-certificates \
    lsb-release apt-transport-https gnupg openssl unzip || log_fail "Web stack base package install failed. Apache, MariaDB, Redis or base tooling may be partially installed."

# Sury is used because personal hosting sometimes needs legacy PHP beside the
# current default; co-installable versions keep old sites contained.
log_info "Configuring Sury PHP repository for co-installable PHP versions including PHP 7.4."
if [[ ! -f "${SURY_KEYRING}" ]]; then
    log_run bash -c "curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o '${SURY_KEYRING}'" || log_fail "Could not install Sury PHP keyring. PHP packages from Sury were not installed."
fi

codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [signed-by=${SURY_KEYRING}] https://packages.sury.org/php/ ${codename} main" > "${SURY_LIST}" \
    || log_fail "Could not write Sury PHP APT source list: ${SURY_LIST}. PHP packages from Sury were not installed."
log_run apt-get update || log_fail "apt-get update failed after adding Sury repository. PHP version installation was not attempted."

for php_version in "${PHP_VERSIONS[@]}"; do
    log_info "Installing PHP ${php_version} with Laravel-friendly extensions."
    log_run apt-get install -y \
        "php${php_version}-cli" "php${php_version}-fpm" "php${php_version}-common" \
        "php${php_version}-mysql" "php${php_version}-mbstring" "php${php_version}-xml" \
        "php${php_version}-curl" "php${php_version}-zip" "php${php_version}-bcmath" \
        "php${php_version}-intl" "php${php_version}-gd" "php${php_version}-readline" \
        "php${php_version}-opcache" "php${php_version}-redis" || log_fail "Could not install PHP ${php_version} and required extensions. Later site creation for this PHP version will log_fail until this is fixed."
    svc_enable_now "php${php_version}-fpm" || log_fail "Could not enable PHP-FPM ${php_version}. The packages may be installed, but the service is not ready for sites."
done

if command -v "php${DEFAULT_PHP_VERSION}" >/dev/null 2>&1; then
    log_run update-alternatives --set php "/usr/bin/php${DEFAULT_PHP_VERSION}" || log_warn "Could not set default CLI PHP."
fi

# Apache is kept as the stable front door; PHP runs through FPM so each site can
# have its own pool and user rather than sharing mod_php process state.
log_info "Enabling Apache modules."
log_run a2enmod rewrite headers ssl proxy_fcgi setenvif http2 expires deflate proxy proxy_http remoteip || log_fail "Could not enable required Apache modules. Apache was not restarted."
a2dismod php8.4 php7.4 >>"${LOG_FILE}" 2>&1 || true

# Validate before restart because Apache is shared infrastructure: one broken
# module/vhost should not take every personal site offline.
svc_enable_now apache2 || log_fail "Could not enable Apache. Web stack setup stopped before Apache restart validation."
apache_restart_safely || log_fail "Apache config validation or restart failed. Apache may still be running with the previous configuration."

# MariaDB is allowed to listen remotely, so TLS is configured as part of the
# service baseline rather than relying on every database user to remember it.
log_info "Preparing MariaDB TLS files."
install -d -m 750 -o mysql -g mysql "${MARIADB_SSL_DIR}" \
    || log_fail "Could not create MariaDB TLS directory: ${MARIADB_SSL_DIR}. MariaDB TLS was not configured."

if [[ ! -f "${MARIADB_CA_CERT}" ]]; then
    log_run bash -c "openssl genrsa 4096 > '${MARIADB_CA_KEY}'" || log_fail "Could not generate MariaDB CA key. MariaDB TLS config was not applied."
    log_run openssl req -new -x509 -nodes -days 3650 \
        -key "${MARIADB_CA_KEY}" \
        -out "${MARIADB_CA_CERT}" \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)-MariaDB-CA" || log_fail "Could not generate MariaDB CA certificate. MariaDB TLS config was not applied."
fi

if [[ ! -f "${MARIADB_SERVER_CERT}" ]]; then
    log_run openssl req -newkey rsa:4096 -days 3650 -nodes \
        -keyout "${MARIADB_SERVER_KEY}" \
        -out "${MARIADB_SERVER_CSR}" \
        -subj "/CN=$(hostname -f 2>/dev/null || hostname)" || log_fail "Could not generate MariaDB server CSR. MariaDB TLS config was not applied."
    log_run openssl x509 -req -in "${MARIADB_SERVER_CSR}" \
        -days 3650 \
        -CA "${MARIADB_CA_CERT}" \
        -CAkey "${MARIADB_CA_KEY}" \
        -set_serial 01 \
        -out "${MARIADB_SERVER_CERT}" || log_fail "Could not sign MariaDB server certificate. MariaDB TLS config was not applied."
fi

log_run chown -R mysql:mysql "${MARIADB_SSL_DIR}" || log_fail "Could not set MariaDB TLS directory ownership. MariaDB restart was not attempted."
log_run chmod 600 "${MARIADB_CA_KEY}" "${MARIADB_SERVER_KEY}" || log_fail "Could not secure MariaDB private keys. MariaDB restart was not attempted."
log_run chmod 644 "${MARIADB_CA_CERT}" "${MARIADB_SERVER_CERT}" || log_fail "Could not set MariaDB certificate permissions. MariaDB restart was not attempted."

tmp_mariadb="$(mktemp)"
cat >"${tmp_mariadb}" <<EOF
$(file_managed_header "core_webstack_apache_php_mariadb_redis.sh")
[mariadb]
bind-address = 0.0.0.0
port = ${MARIADB_PORT}
require_secure_transport = ON
ssl-ca = ${MARIADB_CA_CERT}
ssl-cert = ${MARIADB_SERVER_CERT}
ssl-key = ${MARIADB_SERVER_KEY}
EOF

file_write_managed "${MARIADB_REMOTE_SSL_CONFIG}" 0644 root:root "${tmp_mariadb}" || log_fail "Could not write MariaDB TLS config. MariaDB restart was not attempted."

# MariaDB config is validated before restart for the same reason as Apache: a
# bad generated snippet should log_fail safely before the daemon is disrupted.
svc_enable_now mariadb || log_fail "Could not enable MariaDB. TLS config may be written, but service state was not changed."
mariadb_restart_safely || log_fail "MariaDB config validation or restart failed. MariaDB may still be running with the previous configuration."

# Redis is kept local-only because Laravel typically uses it as an application
# dependency, not as a public network service.
log_info "Configuring Redis as local-only."
file_backup /etc/redis/redis.conf || log_fail "Could not back up redis.conf. Redis config was not edited."
sed -i -E "s/^bind .*/bind ${REDIS_BIND}/" /etc/redis/redis.conf \
    || log_fail "Could not set Redis bind address. Redis was not restarted."
sed -i -E "s/^protected-mode .*/protected-mode yes/" /etc/redis/redis.conf \
    || log_fail "Could not enable Redis protected mode. Redis was not restarted."

svc_enable_now redis-server || log_fail "Could not enable Redis. Redis config may have been edited, but service state was not changed."
redis_restart_safely || log_fail "Could not restart Redis after local-only config update. Redis may still be running with previous settings."

if ! cat >"${SERVER_ADMIN_MARIADB_DIR}/README.txt" <<EOF
MariaDB TLS notes
=================

Authoritative MariaDB TLS files live in:

  ${MARIADB_SSL_DIR}

MariaDB TLS config:
  ${MARIADB_REMOTE_SSL_CONFIG}

Remote users should be created with REQUIRE SSL.
REQUIRE X509 is intentionally not used at this stage.
EOF
then
    log_fail "Could not write MariaDB TLS notes file: ${SERVER_ADMIN_MARIADB_DIR}/README.txt."
fi

log_ok "Web stack installed."
