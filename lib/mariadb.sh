#!/usr/bin/env bash
###############################################################################
# MARIADB HELPERS
#
# Sourced by lib/common.sh. Functions are namespaced because Bash has no real
# module system. These helpers should provide reusable vocabulary; calling
# scripts should own workflow and presentation decisions.
###############################################################################

mariadb_socket_query() {
    mariadb --protocol=socket "$@"
}


mariadb_get_variable_value() {
    local variable_name="$1"

    mariadb_socket_query -NBe "SHOW VARIABLES LIKE '${variable_name}';" | awk '{ print $2 }'
}


mariadb_require_secure_transport_enabled() {
    [[ "$(mariadb_get_variable_value require_secure_transport)" == "ON" ]]
}
