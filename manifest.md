# Server Setup Toolkit Manifest

**Toolkit version:** 0.1.0  
**Target OS:** Debian 13  
**Status:** Authoritative design contract for the Git repository version

This manifest is the source of truth for the Server Setup Toolkit. Scripts, documentation, and future changes should conform to this document. If an implementation conflicts with this manifest, the manifest wins.

For practical usage instructions, see:

```text
README.md
```

---

## 1. Purpose

The toolkit provisions and manages a Debian 13 web-hosting server for multiple HTTPS websites, including Laravel sites.

It is intended for a small/administered hosting environment where readability, repeatability, and safe reruns matter more than invisible automation.

The toolkit should remain:

- plain Bash
- Git-managed
- self-contained
- readable at 2 a.m.
- idempotent where practical
- interactive where risky or context-dependent
- explicit about why actions are being taken

---

## 2. Deployment model

The toolkit is deployed from a Git repository.

There is no bundle, extractor, or build stage in the active workflow.

The repository itself is normally cloned to:

```text
/root/server-admin/
```

Typical first-use flow:

```bash
apt update
apt install -y git
git clone <repo-url> /root/server-admin
cd /root/server-admin

cp config.example.sh config.sh
nano config.sh

sudo ./run_server_setup.sh
```

The path `/root/server-admin` is the recommended deployment location, but scripts should still resolve repository files relative to the repository root rather than assuming a fixed absolute path.

`config.example.sh` is tracked in Git.  
`config.sh` is local to each server and must not be committed.

---

## 3. Repository layout

All repository-controlled paths should use lowercase names and underscores, except where a Git repository/root directory name naturally contains a hyphen.

Authoritative repository layout:

```text
/root/server-admin/
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

Important distinction:

- `/root/server-admin` is the repository root and overall toolkit/admin directory.
- `/root/server-admin/scripts` is only a subfolder inside the repo containing the core and site operational scripts.
- `run_server_setup.sh` lives at the repository root, not inside `scripts/`.

There should be no required files named:

```text
server_setup_bundle.sh
extract_server_setup.sh
build_bundle.sh
```

Those belonged to the older bundle-based design and are no longer part of the active architecture.

---

## 4. Non-goals

The toolkit must not include:

- FTP
- phpMyAdmin
- Supervisor
- Docker
- Certbot
- self-signed/snakeoil HTTPS site certificates
- automatic full-stack orchestration
- hidden state databases
- complex rollback engines
- symlink-based convenience copies of authoritative files
- duplicate/shadow copies of authoritative system files

---

## 5. Runtime server admin layout

Primary runtime admin/repository directory:

```text
/root/server-admin/
```

This directory name may contain a hyphen because Git repository names commonly do. That is accepted as an external naming idiosyncrasy.

Expected runtime layout:

```text
/root/server-admin/
├── config.example.sh
├── config.sh
├── run_server_setup.sh
├── lib/
├── scripts/
├── docs/
├── logs/
├── ssl-certificates/
├── backups/
└── mariadb/
```

### Runtime directory meanings

#### `scripts/`

Contains only the operational core and site scripts.

It does **not** contain the main menu script.

#### `run_server_setup.sh`

Root-level interactive menu for running operational scripts.

#### `logs/`

Contains toolkit script logs only.

Log names use:

```text
<script_name>_<yyyy-mm-dd_hhmmss>.log
```

No global run directory.  
No `latest.log`.

#### `ssl-certificates/`

Authoritative paid SSL certificate storage.

Example:

```text
/root/server-admin/ssl-certificates/example.com/
├── cert.pem
├── privkey.pem
├── chain.pem
├── fullchain.pem
└── source-files.txt
```

Apache HTTPS vhosts reference these files directly.

#### `backups/`

Contains backups created by toolkit scripts before overwriting managed files.

Backups use flattened path names and timestamps.

Example:

```text
/root/server-admin/backups/etc-apache2-sites-available-shop.example.com.conf_2026-05-18_150000.bak
```

#### `mariadb/`

Documentation only.

It must not contain copied or symlinked MariaDB TLS files.

It should contain a README explaining the authoritative MariaDB TLS locations.

#### `docs/`

Human-readable toolkit and server notes.

---

## 6. Authoritative file principle

There must be one authoritative location for each file.

If a system service expects files in a particular location, those files remain there.

The toolkit may document those locations and may back them up before changes, but must not create misleading duplicate copies.

### Authoritative system locations

```text
Apache vhosts:
  /etc/apache2/sites-available/

PHP-FPM pools:
  /etc/php/*/fpm/pool.d/

SSH config:
  /etc/ssh/sshd_config

Redis config:
  /etc/redis/redis.conf

MariaDB TLS files:
  /etc/mysql/ssl/

MariaDB TLS config:
  /etc/mysql/mariadb.conf.d/60-remote-ssl.cnf
```

### Paid website SSL exception

Paid website SSL certificates are authoritative under:

```text
/root/server-admin/ssl-certificates/
```

because these are human-managed website administration files and Apache can reference them directly.

---

## 7. Naming conventions

Use lowercase and underscores for repository-controlled filenames.

The accepted exception is the runtime/repository root directory name:

```text
/root/server-admin/
```

because Git repository names often use hyphens.

### Root files

```text
config.example.sh
config.sh
run_server_setup.sh
README.md
manifest.md
```

### Core setup scripts

Numbered prefixes show suggested execution order only. They do not imply a single global run.

```text
scripts/01_core_base_admin_security.sh
scripts/02_core_firewall.sh
scripts/03_core_webstack_apache_php_mariadb_redis.sh
scripts/04_core_composer.sh
scripts/05_core_disable_root_ssh.sh
```

### Site management scripts

```text
scripts/site_create_website_user.sh
scripts/site_import_paid_certificate.sh
scripts/site_create_https_vhost.sh
scripts/site_create_mariadb_user.sh
```

### Shared library

```text
lib/common.sh
```

---

## 8. Git ignore policy

`.gitignore` should exclude local/runtime files such as:

```gitignore
config.sh
logs/
backups/
ssl-certificates/
mariadb/
*.log
```

`config.example.sh` must remain tracked.

---

## 9. Config contract

Tracked template:

```text
config.example.sh
```

Local server config:

```text
config.sh
```

Scripts source `config.sh`, not `config.example.sh`.

If `config.sh` is missing, operational scripts should exit with a clear explanation such as:

```text
config.sh not found.

Create it with:
  cp config.example.sh config.sh
  nano config.sh
```

`config.sh` must define at least:

```bash
SERVER_SETUP_TOOLKIT_VERSION="0.1.0"

ADMIN_USER="..."
ADMIN_SSH_PUBLIC_KEY_FILE="/root/${ADMIN_USER}.pub"

TIMEZONE="Europe/London"

SSH_PORT="22"
MARIADB_PORT="3306"

PHP_VERSIONS=("8.4" "7.4")
DEFAULT_PHP_VERSION="8.4"

SERVER_ADMIN_DIR="/root/server-admin"
SERVER_ADMIN_SCRIPTS_DIR="${SERVER_ADMIN_DIR}/scripts"
SERVER_ADMIN_LOG_DIR="${SERVER_ADMIN_DIR}/logs"
SERVER_ADMIN_BACKUP_DIR="${SERVER_ADMIN_DIR}/backups"
SERVER_ADMIN_SSL_DIR="${SERVER_ADMIN_DIR}/ssl-certificates"
SERVER_ADMIN_DOCS_DIR="${SERVER_ADMIN_DIR}/docs"
SERVER_ADMIN_MARIADB_DIR="${SERVER_ADMIN_DIR}/mariadb"

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
```

---

## 10. Shared library contract

File:

```text
lib/common.sh
```

All operational scripts source this file.

`common.sh` must reliably locate:

- repository root
- `config.sh`
- caller script name
- runtime log path

It must work when called from:

- `run_server_setup.sh` in the repository root
- scripts under `scripts/`

Recommended behaviour:

1. Determine the caller script path from `BASH_SOURCE[1]`.
2. Determine the caller directory.
3. If the caller directory contains `config.sh`, that directory is the repository root.
4. Otherwise, if the parent of the caller directory contains `config.sh`, that parent is the repository root.
5. Otherwise, exit with a clear message explaining that `config.sh` is missing and showing how to create it.

It must provide at least:

```bash
info
warn
ok
fail
require_root
confirm
run
backup_file
write_managed_file
hostname_to_username
validate_hostname
check_cert_covers_hostname
managed_header
```

### `require_root`

Every operational script, including `run_server_setup.sh`, must call `require_root`.

If not run as root or with sudo, the script exits with a clear explanation and an example:

```text
sudo ./run_server_setup.sh
sudo ./scripts/01_core_base_admin_security.sh
```

It must not silently auto-sudo.

### `run`

Runs commands with:

- concise terminal output by default
- full output written to a timestamped log file
- `--verbose` support to show full command output live and write it to the log
- last 40 log lines shown on failure

### Logging

Operational scripts support:

```text
--verbose
```

Logs are written to:

```text
${SERVER_ADMIN_LOG_DIR}/<script_name>_<timestamp>.log
```

No log files are written to `/var/log`.

### Comments

Comments should explain why, not merely restate what the next command does.

---

## 11. Script source pattern

Scripts under `scripts/` should source `common.sh` using a repo-root-aware pattern.

Recommended:

```bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
source "${repo_root}/lib/common.sh" "$@"
```

`run_server_setup.sh` lives in repo root and should source:

```bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/common.sh" "$@"
```

No operational script should assume that the repository is cloned to a particular path.

---

## 12. Idempotency rules

General behaviour:

```text
missing -> create
same -> skip
important difference -> ask
dangerous -> explain + confirm
```

Specific expectations:

- users are created only if missing
- directories use `install -d`
- packages may be installed repeatedly via `apt-get install -y`
- SSH config changes must avoid duplicate entries
- `AllowUsers` should preserve existing users and ensure the admin user is included
- UFW must not reset rules by default
- Composer should skip or prompt if already installed
- NVM should skip or prompt if already installed
- generated files are backed up before overwrite
- unchanged files are skipped
- disabling root SSH requires explicit typed confirmation
- website certificate replacement backs up old files first

---

## 13. Runner/menu contract

File:

```text
run_server_setup.sh
```

Purpose:

Interactive menu to run scripts without manually typing script names.

Requirements:

- must call `require_root`
- does not auto-sudo
- groups scripts into:
  - Core setup
  - Website management
- displays numbered scripts
- allows `q` / `Q` to quit
- asks whether to run selected script with `--verbose`
- returns to menu after script finishes
- references scripts under `scripts/`
- menu entries must match actual filenames

---

## 14. Core setup scripts

### `scripts/01_core_base_admin_security.sh`

Responsibilities:

- verify Debian 13, warn if not
- install base tools
- create/administer `ADMIN_USER`
- add admin user to sudo
- set local sudo password if requested
- install SSH public key
- disable SSH password authentication
- set:
  - `PermitEmptyPasswords no`
  - `PubkeyAuthentication yes`
  - `PasswordAuthentication no`
  - `KbdInteractiveAuthentication no`
  - `MaxAuthTries 3`
  - `AllowUsers <admin>`
- preserve existing `AllowUsers` entries
- install/configure fail2ban
- configure unattended security updates only
- must not disable root SSH login

Must not install `software-properties-common`.

### `scripts/02_core_firewall.sh`

Responsibilities:

- install/enable UFW
- default deny incoming
- default allow outgoing
- allow:
  - SSH port
  - 80/tcp for HTTP-to-HTTPS redirect
  - 443/tcp for HTTPS
  - MariaDB port for TLS-protected remote access
- must not reset existing UFW rules by default

### `scripts/03_core_webstack_apache_php_mariadb_redis.sh`

Responsibilities:

- install Apache
- install MariaDB
- install Redis
- configure Sury PHP repository
- install PHP 8.4 and PHP 7.4 with PHP-FPM
- install Laravel-friendly PHP extensions
- enable Apache modules:
  - rewrite
  - headers
  - ssl
  - proxy_fcgi
  - setenvif
  - http2
  - expires
  - deflate
  - proxy
  - proxy_http
  - remoteip
- configure MariaDB remote access with TLS required
- generate MariaDB TLS certs only if missing
- keep MariaDB TLS authoritative files in `/etc/mysql/ssl`
- create `${SERVER_ADMIN_MARIADB_DIR}/README.txt` documenting authoritative locations
- configure Redis local-only

### `scripts/04_core_composer.sh`

Responsibilities:

- install Composer globally
- verify installer signature
- if Composer exists, prompt before updating/reinstalling
- use `COMPOSER_ALLOW_SUPERUSER=1` only for root-run version checks

### `scripts/05_core_disable_root_ssh.sh`

Responsibilities:

- require explicit typed confirmation
- set `PermitRootLogin no`
- validate sshd config before reload
- reload SSH
- only run after admin SSH login and sudo are confirmed

---

## 15. Website model

All websites are HTTPS-only.

HTTP vhosts exist only to redirect to HTTPS.

No HTTP-only website mode.

No custom default catch-all site.

### Site paths

Each site uses:

```text
/home/<siteuser>/site
/home/<siteuser>/logs
/home/<siteuser>/tmp
/home/<siteuser>/.ssh
/home/<siteuser>/.nvm
```

Laravel document root:

```text
/home/<siteuser>/site/public
```

Non-Laravel document root:

```text
/home/<siteuser>/site
```

### Site usernames

Site usernames are derived from full hostnames by default.

Example:

```text
shop.example.com -> shop_example_com
shop.domain1.co.uk -> shop_domain1_co_uk
shop.domain2.co.uk -> shop_domain2_co_uk
```

Scripts may allow override, but default must be hostname-derived.

Reason: avoids collisions across multiple base domains with the same subdomain.

---

## 16. Site management scripts

### `scripts/site_create_website_user.sh`

Responsibilities:

- prompt for primary hostname
- derive default Linux username from hostname
- create site Linux user if missing
- create standard site directories
- configure `.ssh/authorized_keys`
- install NVM for the site user if requested and not already installed
- optionally install a selected Node version
- ownership model:
  - `<siteuser>:<siteuser>`

### `scripts/site_import_paid_certificate.sh`

Responsibilities:

- prompt for certificate folder/domain
- prompt for input directory containing uploaded cert files
- only allow files inside the selected input directory
- support:
  - private key file
  - leaf certificate file
  - fullchain file
  - intermediate ZIP file
  - loose intermediate files
- validate PEM BEGIN/END certificate balance
- detect likely fullchain files by certificate count
- build:
  - `cert.pem`
  - `privkey.pem`
  - `chain.pem`
  - `fullchain.pem`
  - `source-files.txt`
- store files under:
  - `${SERVER_ADMIN_SSL_DIR}/<certificate-folder>/`
- validate private key matches certificate
- set secure permissions
- backup existing certificate files before overwrite

### `scripts/site_create_https_vhost.sh`

Responsibilities:

- prompt for hostname
- derive default site user from hostname
- prompt for extra aliases
- prompt PHP version
- prompt Laravel/non-Laravel mode
- offer certificate choice:
  - use existing certificate
  - import new paid certificate
- support wildcard cert reuse
- certificate folder default for `shop.example.com` should be `example.com`
- validate that certificate appears to cover hostname
- warn and require confirmation on mismatch
- create isolated PHP-FPM pool as the site user
- create HTTP vhost that redirects to HTTPS
- create HTTPS vhost using:
  - `fullchain.pem`
  - `privkey.pem`
- enable site
- validate Apache config before reload
- restart relevant PHP-FPM service
- reload Apache

### `scripts/site_create_mariadb_user.sh`

Responsibilities:

- prompt for DB name
- prompt for DB username
- prompt for host pattern, default `%`
- prompt for password
- create database if missing
- create/update user with:
  - `REQUIRE SSL`
- grant privileges for that database

---

## 17. SSL policy

Website HTTPS certificates must be paid/real certificates supplied by the admin.

No self-signed/snakeoil website certificate creation.

Wildcard certificates are expected and supported.

Multiple subdomain sites may reuse one wildcard certificate folder.

Example:

```text
Hostname:
  shop.example.com

Certificate folder:
  example.com

Certificate SAN:
  *.example.com
```

HSTS should not be enabled by default. It may be included as a commented-out vhost line with an explanatory comment.

---

## 18. MariaDB policy

MariaDB is accessible remotely and locally.

MariaDB remote connections must require TLS:

```text
require_secure_transport = ON
```

Database users should be created with:

```sql
REQUIRE SSL
```

`REQUIRE X509` is intentionally not used for now.

MariaDB TLS runtime files live under:

```text
/etc/mysql/ssl/
```

No duplicate MariaDB cert copies under `/root/server-admin`.

---

## 19. Redis policy

Redis is installed because Laravel sites may need it.

Redis must remain local-only:

```text
bind 127.0.0.1 ::1
protected-mode yes
```

No firewall port is opened for Redis.

---

## 20. Apache/PHP policy

Apache uses PHP-FPM.

Do not use Apache `mod_php`.

Each site gets an isolated PHP-FPM pool running as that site user.

PHP-FPM socket ownership allows Apache to communicate with the pool.

Default PHP versions:

```text
8.4
7.4
```

PHP 7.4 is legacy/EOL and installed only because legacy sites require it.

---

## 21. Laravel assumptions

Laravel support is first-class.

Laravel sites use:

```text
DocumentRoot /home/<siteuser>/site/public
```

Writable directories:

```text
/home/<siteuser>/site/storage
/home/<siteuser>/site/bootstrap/cache
```

The toolkit does not install or configure Supervisor.

---

## 22. Generated file headers

Generated/managed files should include a header explaining:

- managed by toolkit
- toolkit version
- generating script
- timestamp
- manual edits may be overwritten

---

## 23. Testing expectations

Before disabling root SSH:

```text
1. Confirm admin user can SSH in
2. Confirm admin user can use sudo
3. Keep existing root session open while testing
```

Useful checks:

```bash
apache2ctl configtest
php -v
php8.4 -v
php7.4 -v
systemctl status mariadb
systemctl status redis-server
ufw status verbose
```

---

## 24. Knock-on effect checklist

Because the toolkit moved from bundle/extractor deployment to Git deployment, the following must be checked:

- `common.sh` must find `config.sh` from both repo root and `scripts/` callers.
- `run_server_setup.sh` must reference scripts under lowercase `scripts/`.
- all script source lines must use lowercase `scripts/`.
- no file should reference uppercase `Scripts/`.
- no file should reference `extract_server_setup.sh`, `build_bundle.sh`, or `server_setup_bundle.sh`.
- no generated docs should instruct bundle extraction.
- `.gitignore` must ignore `config.sh`.
- deployment docs must say to copy `config.example.sh` to `config.sh`.
- `SERVER_ADMIN_DIR` should default to `/root/server-admin`.
- operational scripts should not assume the repo was cloned to `/root/server-admin`; only runtime storage defaults should use that path.
