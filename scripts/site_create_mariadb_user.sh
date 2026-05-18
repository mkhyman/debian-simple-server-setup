#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh" "$@"
require_root

###############################################################################
# CREATE MARIADB USER
#
# Creates a database and user requiring SSL. REQUIRE X509 is intentionally not
# used yet because client certificate management is deferred.
###############################################################################

read -rp "Database name: " DB_NAME
read -rp "Database username: " DB_USER
read -rp "Database host pattern [%]: " DB_HOST
DB_HOST="${DB_HOST:-%}"

read -rsp "Database user password: " DB_PASS
echo

[[ "${DB_NAME}" =~ ^[a-zA-Z0-9_]+$ ]] || fail "Invalid database name."
[[ "${DB_USER}" =~ ^[a-zA-Z0-9_]+$ ]] || fail "Invalid database username."

mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}' REQUIRE SSL;
ALTER USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}' REQUIRE SSL;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL

ok "MariaDB database/user created."
info "Database: ${DB_NAME}"
info "User requires SSL: '${DB_USER}'@'${DB_HOST}'"
