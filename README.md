# NetBird migration from Zitadel IdP to embedded Dex IdP

This repository provides a guided migration flow for self-hosted NetBird deployments
that still use the legacy 5-container Docker stack with external Zitadel authentication.

The main script, `netbird-migrate-from-zitadel.sh`, is an attempt to automate the migration as much as possible, as described in the migration:
https://docs.netbird.io/selfhosted/migration/external-to-embedded-idp

## Key features

- Safe by default (`dry-run` first).
- Built-in compatibility check against latest NetBird release.
- Automatic backup creation before destructive changes.
- Automatic `dashboard.env` key updates via `set_env_var` helper.
- Clear operator guidance for manual Caddy route completion.
- Includes rollback script for quick recovery.

## Usage

Download the scripts to your legacy NetBird directory where compose/config files are present.

```bash
curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-migrate-from-zitadel.sh -o netbird-migrate-from-zitadel.sh && chmod +x netbird-migrate-from-zitadel.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-migrate-rollback.sh -o netbird-migrate-rollback.sh && chmod +x netbird-migrate-rollback.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-legacy-update.sh -o netbird-legacy-update.sh && chmod +x netbird-legacy-update.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-legacy-backup.sh -o netbird-legacy-backup.sh && chmod +x netbird-legacy-backup.sh
```

Run from your legacy NetBird directory:

Dry-run (default):

```bash
sudo ./netbird-migrate-from-zitadel.sh
```

Apply migration:

```bash
sudo ./netbird-migrate-from-zitadel.sh --apply
```

Force download latest migration binary:

```bash
sudo ./netbird-migrate-from-zitadel.sh --download
```

Apply + force download:

```bash
sudo ./netbird-migrate-from-zitadel.sh --apply --download
```

## What this migration script actually does

`netbird-migrate-from-zitadel.sh` performs the following workflow:

1. Validates preconditions:
- Checks that migration is still needed (legacy setup, not already `netbird-server`).
- Requires root permissions.
- Verifies the installed legacy management version matches latest upstream release.

2. Gets migration tooling:
- Uses existing `./netbird-idp-migrate` binary, or downloads latest release with `--download`.

3. Validates Zitadel input:
- Requires `netbird-migrate-from-zitadel.env` with `CLIENT_ID` and `CLIENT_SECRET`.

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

- `management.json` (used to infer current issuer/domain)
- `dashboard.env` (updated post-migration)
- Optional `zitadel.env` with `ZITADEL_EXTERNALDOMAIN`
- `netbird-migrate-from-zitadel.env` containing:

```env
CLIENT_ID="..."
CLIENT_SECRET="..."
```

If `netbird-migrate-from-zitadel.env` is missing, the script creates a template and exits.

## Additional scripts (legacy update and recovery helpers)

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
