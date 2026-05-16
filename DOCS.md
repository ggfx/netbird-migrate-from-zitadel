## What this migration script actually does

`netbird-migrate-from-zitadel.sh` performs the following workflow:

1. Validates preconditions:
- Requires root permissions.
- Checks wether migration is still needed (legacy setup, not already `netbird-server`).
- Verifies the installed legacy management version matches latest upstream release.

2. Gets migration tooling:
- Uses existing `./netbird-idp-migrate` binary, or downloads latest release with `--download`.

3. Validates Zitadel input:
- Requires `netbird-migrate-from-zitadel.env` with `CLIENT_ID` and `CLIENT_SECRET`.
- Runs `create-zitadel-netbird-sso-project.sh` to create a Zitadel OIDC Web
Application for NetBird

4. Prepares migration seed:
- Creates a `connector.json` OIDC config for Zitadel.
- Exports `NETBIRD_IDP_SEED_INFO` for the migration tool.

5. Stops management and prepares backups:
- Stops `management` container.
- Detects management Docker volume and data path.
- In `--apply` mode, creates backups for:
	- SQLite DB: `store.db.bak`
	- `management.json.bak`
	- `dashboard.env.bak`

6. Runs migration:
- Default mode is dry-run (safe validation):
	- `./netbird-idp-migrate --domain <domain> --dry-run`
- Apply mode performs real migration:
	- `./netbird-idp-migrate --domain <domain>`

7. Post-migration updates:
- Updates OIDC-related keys in `dashboard.env` automatically.
- Recreates `management` and `dashboard` containers.
- Prints next manual step to route `/oauth2/*` to management in Caddy.

## Required files/inputs

- `dashboard.env` (updated post-migration)
- `zitadel.env` with `ZITADEL_EXTERNALDOMAIN`
- `netbird-migrate-from-zitadel.env` containing:

```env
CLIENT_ID="..."
CLIENT_SECRET="..."
```

If `netbird-migrate-from-zitadel.env` is missing, the script creates a template and exits.

## Additional scripts (legacy update and recovery helpers)

### `create-zitadel-netbird-sso-project.sh`

Helper script used by the migration flow to prepare Zitadel for NetBird SSO.

What it does:
- Validates your Zitadel API access using `MIGRATE_FROM_ZITATEL_PAT`.
- Creates (or reuses) a Zitadel project (default name: `NetBird SSO`).
- Creates an OIDC Web application with NetBird-compatible settings.
- Writes created credentials to `netbird-migrate-from-zitadel.env`.

Requirements:
- `zitadel.env` with `ZITADEL_EXTERNALDOMAIN` and `MIGRATE_FROM_ZITATEL_PAT`.

### `netbird-legacy-update.sh`

Use this before migration when your legacy management version is not the latest.

What it does:
- Compares installed management version with latest GitHub release.
- If outdated, runs backup helper script first.
- Pulls latest images for dashboard, signal, relay, management, coturn, and postgres.
- Restarts the legacy stack.

### `netbird-legacy-backup.sh`

Backup helper used by the legacy update script.

What it does:
- Creates timestamped `legacy-backup-YYYYMMDD-HHMMSS` folder.
- Copies key config files (`docker-compose.yml`, `management.json`, env files, etc.).
- Stops management briefly and copies `/var/lib/netbird/` from container.

### `netbird-migrate-rollback.sh`

Rollback helper for migration failure or validation issues after apply.

What it does:
- Stops management.
- Restores `store.db` from `store.db.bak`.
- Restores `management.json` and `dashboard.env` from `.bak` files.
- Recreates management/dashboard containers.

## Recommended operator workflow

1. Ensure legacy stack is on latest release with `./netbird-legacy-update.sh`.
2. Configure Zitadel web app and set credentials in `netbird-migrate-from-zitadel.env`.
3. Run migration dry-run and review output.
4. Run migration with `--apply`.
5. Update Caddy route for `/oauth2/*`, restart Caddy, verify OIDC discovery endpoint.
6. If needed, rollback with `./netbird-migrate-rollback.sh`.