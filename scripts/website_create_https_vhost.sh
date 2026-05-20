#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
require_root
require_base_system_complete

read -rp "Primary hostname / ServerName, e.g. shop.example.com: " hostname
validate_hostname "${hostname}" || fail "Invalid hostname: ${hostname}"

default_site_user="$(hostname_to_username "${hostname}")"
read -rp "Linux site username [${default_site_user}]: " site_user
site_user="${site_user:-${default_site_user}}"

validate_linux_username "${site_user}" || fail "Invalid Linux username: ${site_user}"

read -rp "Laravel site? [Y/n]: " is_laravel
is_laravel="${is_laravel:-Y}"

if ! is_site_user_ready "${site_user}" "${is_laravel}"; then
    rc=$?
    warn "Website user is not ready for vhost creation."
    warn "Expected user: ${site_user}"
    warn "Expected site root: $(site_root_for_user "${site_user}")"
    warn "Expected document root: $(site_docroot_for_user "${site_user}" "${is_laravel}")"
    fail "Run first: sudo ./scripts/user_website.sh"
fi

read -rp "Extra hostnames / ServerAlias, space-separated or blank: " server_aliases

read -rp "PHP version [${DEFAULT_PHP_VERSION}]: " php_version
php_version="${php_version:-${DEFAULT_PHP_VERSION}}"
require_php_fpm_version "${php_version}" || fail "PHP-FPM ${php_version} is not installed."

echo
echo "SSL certificate options:"
echo "  1) Use existing certificate"
echo "  2) Import new paid certificate"
read -rp "Choice [1]: " cert_choice
cert_choice="${cert_choice:-1}"

if [[ "${cert_choice}" == "2" ]]; then
    "${REPO_ROOT}/scripts/website_import_paid_certificate.sh"
elif [[ "${cert_choice}" != "1" ]]; then
    fail "Invalid certificate choice: ${cert_choice}"
fi

default_cert_folder="${hostname#*.}"
read -rp "Certificate folder/domain [${default_cert_folder}]: " cert_folder
cert_folder="${cert_folder:-${default_cert_folder}}"

require_certificate_files "${cert_folder}" || fail "Missing certificate files for ${cert_folder}."

cert_dir="$(certificate_dir_for_name "${cert_folder}")"
fullchain="${cert_dir}/fullchain.pem"
privkey="${cert_dir}/privkey.pem"

if check_cert_covers_hostname "${fullchain}" "${hostname}"; then
    ok "Certificate appears to cover ${hostname}."
else
    warn "Certificate may not cover ${hostname}."
    confirm "Continue anyway?" || exit 1
fi

site_home="$(site_home_for_user "${site_user}")"
docroot="$(site_docroot_for_user "${site_user}" "${is_laravel}")"
socket="/run/php/php${php_version}-fpm-${site_user}.sock"
pool_file="/etc/php/${php_version}/fpm/pool.d/${site_user}.conf"

tmp_pool="$(mktemp)"
cat >"${tmp_pool}" <<EOF
$(managed_header "website_create_https_vhost.sh")
[${site_user}]
user = ${site_user}
group = ${site_user}

listen = ${socket}
listen.owner = ${APACHE_RUN_USER}
listen.group = ${APACHE_RUN_GROUP}
listen.mode = 0660

pm = ondemand
pm.max_children = 10
pm.process_idle_timeout = 10s
pm.max_requests = 500

php_admin_value[open_basedir] = ${site_home}:/tmp
php_admin_value[upload_tmp_dir] = ${site_home}/${SITE_TMP_DIR}
php_admin_value[session.save_path] = ${site_home}/${SITE_TMP_DIR}
php_admin_value[error_log] = ${site_home}/${SITE_LOG_DIR}/php-error.log
php_admin_flag[log_errors] = on

catch_workers_output = yes
EOF

write_managed_file "${pool_file}" 0644 root:root "${tmp_pool}" || fail "Could not write PHP-FPM pool."

server_alias_line=""
if [[ -n "${server_aliases}" ]]; then
    server_alias_line="    ServerAlias ${server_aliases}"
fi

http_vhost="/etc/apache2/sites-available/${hostname}.conf"
https_vhost="/etc/apache2/sites-available/${hostname}-ssl.conf"

tmp_http="$(mktemp)"
cat >"${tmp_http}" <<EOF
$(managed_header "website_create_https_vhost.sh")
<VirtualHost *:80>
    ServerName ${hostname}
${server_alias_line}

    ErrorLog ${site_home}/${SITE_LOG_DIR}/${hostname}-http-error.log
    CustomLog ${site_home}/${SITE_LOG_DIR}/${hostname}-http-access.log combined

    Redirect permanent / https://${hostname}/
</VirtualHost>
EOF

tmp_https="$(mktemp)"
cat >"${tmp_https}" <<EOF
$(managed_header "website_create_https_vhost.sh")
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName ${hostname}
${server_alias_line}

    DocumentRoot ${docroot}

    ErrorLog ${site_home}/${SITE_LOG_DIR}/${hostname}-ssl-error.log
    CustomLog ${site_home}/${SITE_LOG_DIR}/${hostname}-ssl-access.log combined

    SSLEngine on
    SSLCertificateFile ${fullchain}
    SSLCertificateKeyFile ${privkey}

    Protocols h2 http/1.1

    <Directory ${docroot}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:${socket}|fcgi://localhost/"
    </FilesMatch>

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # HSTS is deliberately not enabled by default.
    # Enable only once all relevant subdomains have working HTTPS.
    # Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>
</IfModule>
EOF

write_managed_file "${http_vhost}" 0644 root:root "${tmp_http}" || fail "Could not write HTTP vhost."
write_managed_file "${https_vhost}" 0644 root:root "${tmp_https}" || fail "Could not write HTTPS vhost."

run a2ensite "${hostname}.conf" || fail "Could not enable HTTP vhost."
run a2ensite "${hostname}-ssl.conf" || fail "Could not enable HTTPS vhost."
run apache2ctl configtest || fail "Apache configtest failed."
run systemctl restart "php${php_version}-fpm" || fail "Could not restart PHP-FPM ${php_version}."
run systemctl reload apache2 || fail "Could not reload Apache."

ok "HTTPS site created for ${hostname}."
