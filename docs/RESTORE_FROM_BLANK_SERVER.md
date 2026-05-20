# Restore from a blank Debian server

This is not an automated restore system. It is a short checklist for future-you
when a server has to be rebuilt quickly and calmly.

## Assumptions

- You are starting from a fresh Debian server.
- You have this toolkit available.
- You have any required website files, `.env` files, uploaded media and database
  dumps available from your own backup location.
- Paid SSL certificates can either be re-imported or reissued.

## Suggested order

1. Copy `config.example.sh` to `config.sh` and adjust it for the server.
2. Run the base system setup:

   ```bash
   sudo ./scripts/core_base_system.sh
   ```

3. Configure firewall, SSH hardening, web stack and Composer using the menu or
   the individual scripts.
4. Recreate admin and website Linux users.
5. Recreate website directory layouts with `scripts/user_website.sh`.
6. Restore each site's application files into its site root.
7. Restore each site's `.env` file and uploaded/storage data.
8. Restore or recreate each MariaDB database and site-specific database user.
9. Import or reissue SSL certificates.
10. Recreate Apache HTTPS vhosts.
11. Run the health checks:

    ```bash
    sudo ./scripts/core_health_check.sh
    sudo ./scripts/user_health_check.sh
    sudo ./scripts/website_health_check.sh
    ```

12. Use `--interactive-fix` on the relevant health check if it reports simple
    ownership, permission or ACL drift that the toolkit can safely repair.

## Backup reminder

The toolkit backs up managed configuration files before replacing them. Those
backups are useful for local rollback, but they are not a full disaster-recovery
backup. A real off-server backup should include website code, `.env` files,
uploaded media/storage, database dumps and any certificates you cannot easily
reissue.
