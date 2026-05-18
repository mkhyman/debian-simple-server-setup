Server Setup Toolkit 0.1.0
==========================

This toolkit is intended for Debian 13 web hosting.

Main admin directory:

  /root/server-admin

Recommended layout:

  /root/server-admin/scripts       extracted setup scripts
  /root/server-admin/logs          script logs
  /root/server-admin/backups       backups made before overwriting managed files
  /root/server-admin/ssl-certificates
                                  authoritative paid SSL certificate storage
  /root/server-admin/mariadb       notes about MariaDB TLS locations
  /root/server-admin/docs          human-readable notes

Naming convention:

  Use underscores in filenames.

Core setup scripts:

  01_core_base_admin_security.sh
  02_core_firewall.sh
  03_core_webstack_apache_php_mariadb_redis.sh
  04_core_composer.sh
  05_core_disable_root_ssh.sh

Website management scripts:

  site_create_website_user.sh
  site_import_paid_certificate.sh
  site_create_https_vhost.sh
  site_create_mariadb_user.sh

Run menu:

  sudo ./run_server_setup.sh

Logs:

  /root/server-admin/logs/<script_name>_<timestamp>.log
