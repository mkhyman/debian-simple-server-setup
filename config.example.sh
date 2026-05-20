#!/usr/bin/env bash
###############################################################################
# SHARED CONFIGURATION EXAMPLE
#
# Server Setup Toolkit Version: 0.1.0
#
# Copy this file to config.sh and edit config.sh for the target server:
#
#   cp config.example.sh config.sh
#   nano config.sh
#
# config.sh is server-specific and should not be committed to Git.
###############################################################################

SERVER_SETUP_TOOLKIT_VERSION="0.1.0"

# Admin users are created/managed by scripts/user_admin.sh.
# This group lets admin users maintain the toolkit repository without using sudo
# for every Git/editing operation.
SERVER_ADMIN_GROUP="server_admin"

TIMEZONE="Europe/London"

SSH_PORT="22"
MARIADB_PORT="3306"

PHP_VERSIONS=("8.4" "7.4")
DEFAULT_PHP_VERSION="8.4"

SERVER_ADMIN_DIR="/server-admin"
SERVER_ADMIN_SCRIPTS_DIR="${SERVER_ADMIN_DIR}/scripts"
SERVER_ADMIN_LOG_DIR="${SERVER_ADMIN_DIR}/logs"
SERVER_ADMIN_BACKUP_DIR="${SERVER_ADMIN_DIR}/backups"
SERVER_ADMIN_SSL_DIR="${SERVER_ADMIN_DIR}/ssl-certificates"
SERVER_ADMIN_DOCS_DIR="${SERVER_ADMIN_DIR}/docs"
SERVER_ADMIN_MARIADB_DIR="${SERVER_ADMIN_DIR}/mariadb"
SERVER_ADMIN_STATE_DIR="${SERVER_ADMIN_DIR}/.state"
BASE_SYSTEM_COMPLETE_FILE="${SERVER_ADMIN_STATE_DIR}/base_system_complete"

SURY_KEYRING="/usr/share/keyrings/debsuryorg-archive-keyring.gpg"
SURY_LIST="/etc/apt/sources.list.d/php-sury.list"

MARIADB_SSL_DIR="/etc/mysql/ssl"
MARIADB_CA_KEY="${MARIADB_SSL_DIR}/ca-key.pem"
MARIADB_CA_CERT="${MARIADB_SSL_DIR}/ca.pem"
MARIADB_SERVER_KEY="${MARIADB_SSL_DIR}/server-key.pem"
MARIADB_SERVER_CSR="${MARIADB_SSL_DIR}/server-req.pem"
MARIADB_SERVER_CERT="${MARIADB_SSL_DIR}/server-cert.pem"
MARIADB_REMOTE_SSL_CONFIG="/etc/mysql/mariadb.conf.d/60-remote-ssl.cnf"

REDIS_BIND="127.0.0.1 ::1"

SITE_BASE_DIR="/home"
SITE_DOC_DIR="site"
SITE_LOG_DIR="logs"
SITE_TMP_DIR="tmp"

APACHE_RUN_USER="www-data"
APACHE_RUN_GROUP="www-data"

ENABLE_UNATTENDED_SECURITY_UPDATES="yes"
INTERACTIVE_CONFIRMATIONS="yes"
