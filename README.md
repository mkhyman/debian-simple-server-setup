# Debian Simple Server Setup

Bash scripts for preparing a Debian 13 server for HTTPS website hosting.

The toolkit is intended for a small administered server using:

- Apache with PHP-FPM
- multiple PHP versions
- MariaDB with TLS-required remote access
- Redis local-only
- paid SSL certificates
- Laravel-friendly site layout
- per-site Linux users
- SSH/SFTP access only

It deliberately avoids FTP, phpMyAdmin, Supervisor, Docker, Certbot, and self-signed website certificates.

---

## Install

Initial installation is normally done as root because the admin user may not exist yet.

```bash
apt update
apt install -y git dos2unix
git clone <repo-url> /server-admin
cd /server-admin
```

Create local config:

```bash
cp config.example.sh config.sh
nano config.sh
```

If the files have passed through Windows/WSL, normalise line endings:

```bash
find . -type f -not -path "./.git/*" -exec dos2unix {} +
```

Run the menu:

```bash
./run_server_setup.sh
```

The first menu run checks whether base system setup has completed. If not, it offers to run it first.

After an admin user has been created and tested:

```bash
ssh <admin-user>@server
cd /server-admin
sudo ./run_server_setup.sh
```

---

## Rerunning scripts

Scripts are intended to be safe to rerun:

- unchanged managed files are skipped
- changed managed files are backed up before replacement
- potentially destructive overwrites ask for confirmation
- scripts should not append duplicate configuration

If a script refuses to run, read the message first; it is usually protecting a dependency such as the base-system marker or a missing website user.

## Runtime locations

Default runtime/admin directory:

```text
/server-admin
```

Important folders:

```text
/server-admin/logs
/server-admin/backups
/server-admin/ssl-certificates
/server-admin/.state
```

Paid certificate files are stored under:

```text
/server-admin/ssl-certificates/<certificate-folder>/
```

For example:

```text
/server-admin/ssl-certificates/example.com/fullchain.pem
/server-admin/ssl-certificates/example.com/privkey.pem
```

---

## Main scripts

Use the menu where possible:

```bash
sudo ./run_server_setup.sh
```

Scripts are grouped as:

```text
Core
User
Website
```

The base system script must be run before the other scripts. Directly-run scripts enforce this using a state marker.

---

## Notes

`config.sh` is local server state and should not be committed.

The repository is group-maintainable via the `server_admin` group, while sensitive certificate private keys remain root-only.
