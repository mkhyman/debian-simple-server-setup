#!/usr/bin/env bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
user_require_root
state_require_base_system_complete

read -rp "Database name: " db_name
read -rp "Database username: " db_user
read -rp "Database host pattern [%]: " db_host
db_host="${db_host:-%}"
read -rsp "Database user password: " db_pass
echo

[[ "${db_name}" =~ ^[a-zA-Z0-9_]+$ ]] || log_fail "Invalid database name."
[[ "${db_user}" =~ ^[a-zA-Z0-9_]+$ ]] || log_fail "Invalid database username."

if ! mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'${db_host}' IDENTIFIED BY '${db_pass}' REQUIRE SSL;
ALTER USER '${db_user}'@'${db_host}' IDENTIFIED BY '${db_pass}' REQUIRE SSL;
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'${db_host}';
FLUSH PRIVILEGES;
SQL
then
    log_fail "MariaDB user/database creation failed. The database or user may be partially created; check MariaDB before rerunning."
fi

log_ok "MariaDB database/user created."
log_info "User requires SSL: '${db_user}'@'${db_host}'"
