# Server Setup Toolkit

**Version:** 0.1.0  
**Target OS:** Debian 13

A Bash-based toolkit for setting up and maintaining a Debian 13 web-hosting server.

It is designed for:

- Apache + PHP-FPM hosting
- multiple PHP versions
- Laravel sites
- paid SSL certificates
- wildcard certificate reuse
- MariaDB with TLS-required remote access
- Redis local-only
- per-site Linux users
- SFTP/SSH-only administration

This project is intentionally plain Bash. It is meant to be readable, editable, and understandable months later.

For the design rules and implementation contract, see:

```text
manifest.md
```

---

## Repository layout

```text
repo-root/
├── .gitignore
├── config.example.sh
├── config.sh                 # local only, ignored by Git
├── run_server_setup.sh        # main menu script
├── README.md
├── manifest.md
├── lib/
│   └── common.sh
├── scripts/
│   ├── 01_core_base_admin_security.sh
│   ├── 02_core_firewall.sh
│   ├── 03_core_webstack_apache_php_mariadb_redis.sh
│   ├── 04_core_composer.sh
│   ├── 05_core_disable_root_ssh.sh
│   ├── site_create_website_user.sh
│   ├── site_import_paid_certificate.sh
│   ├── site_create_https_vhost.sh
│   └── site_create_mariadb_user.sh
└── docs/
    └── readme.txt
```

---

## Initial deployment

Clone the repository:

```bash
apt update
apt install -y git
git clone <repo-url> /server-admin
cd /server-admin
```

Create local config:

```bash
cp config.example.sh config.sh
nano config.sh
```

Run the menu:

```bash
sudo ./run_server_setup.sh
```

The toolkit does **not** auto-sudo. Run it explicitly with `sudo` or as root.

---

## Suggested core setup order

Use the menu, or run scripts directly:

```bash
sudo ./scripts/01_core_base_admin_security.sh
sudo ./scripts/02_core_firewall.sh
sudo ./scripts/03_core_webstack_apache_php_mariadb_redis.sh
sudo ./scripts/04_core_composer.sh
```

Only after confirming the admin user can SSH in and use sudo:

```bash
sudo ./scripts/05_core_disable_root_ssh.sh
```

Before disabling root SSH, keep the current root session open and test from a new terminal:

```bash
ssh <admin-user>@your-server
sudo -v
```

---

## Website workflow

Typical website setup:

```bash
sudo ./scripts/site_create_website_user.sh
sudo ./scripts/site_import_paid_certificate.sh
sudo ./scripts/site_create_https_vhost.sh
sudo ./scripts/site_create_mariadb_user.sh
```

The vhost script can also use an existing imported wildcard certificate.

Example:

```text
hostname:           shop.example.com
site user:          shop_example_com
certificate folder: example.com
certificate SAN:    *.example.com
```

---

## Runtime layout

By default, runtime/admin files live under:

```text
/server-admin/
```

Expected runtime folders:

```text
/server-admin/
├── logs/
├── ssl-certificates/
├── backups/
├── mariadb/
└── docs/
```

The repository itself also normally lives at:

```text
/server-admin/
```

The toolkit should still resolve its own files relative to the repository root, not by assuming an absolute clone path.

---

## Logs

Script logs are written to:

```text
/server-admin/logs/
```

Log names look like:

```text
<script_name>_<yyyy-mm-dd_hhmmss>.log
```

Example:

```text
03_core_webstack_apache_php_mariadb_redis_2026-05-18_150501.log
```

Use `--verbose` to show command output live:

```bash
sudo ./scripts/03_core_webstack_apache_php_mariadb_redis.sh --verbose
```

---

## Paid SSL certificates

Paid website certificates are authoritative under:

```text
/server-admin/ssl-certificates/
```

Example:

```text
/server-admin/ssl-certificates/example.com/
├── cert.pem
├── privkey.pem
├── chain.pem
├── fullchain.pem
└── source-files.txt
```

Apache vhosts reference:

```text
fullchain.pem
privkey.pem
```

The toolkit does not create self-signed/snakeoil website certificates.

---

## Important exclusions

This toolkit intentionally does **not** include:

- FTP
- phpMyAdmin
- Supervisor
- Docker
- Certbot
- self-signed website certificates
- bundle/extractor/build tooling

---

## Notes

This started life as “just a setup script” and grew arms.

That is fine.

The aim is not minimalism at all costs; the aim is boring, readable, maintainable server tooling.
