# NetBird migration from Zitadel IdP to embedded Dex IdP

This repository provides a guided migration flow for self-hosted NetBird deployments
using the legacy multi-container Docker setup with external Zitadel authentication.

The main script, `netbird-migrate-from-zitadel.sh`, is an attempt to automate as much as possible from the [official migration guide](https://docs.netbird.io/selfhosted/migration/external-to-embedded-idp).

## Key features

- Safe by default (`dry-run` first).
- Built-in compatibility check against latest NetBird release.
- Automatic backup creation before destructive changes.
- Automatic creation of a OIDC Web Application via Zitadel v1 API.
- Automatic `dashboard.env` key updates via `set_env_var` helper.
- Clear operator guidance for Caddy route completion.
- Includes rollback script for quick recovery.

## Requisites

A Zitadel OIDC web application for Netbird is required.
A **Personal Access Token (PAT)** with Org Owner permission is necessary for the script to create this automatically.

Login to Zitadel as Administrator, go to Users -> service-users, choose _zitadel-admin-sa_ -> Personal Access Tokens and click on New.

Create one with very short expiration (1 day).
![Create service user PAT](assets/zitadel-service-user-pat-00.png)<br>

**Copy the Token to the file `netbird-migrate-from-zitadel.env` in Netbird directory** (if the file is missing, create it):
```sh
MIGRATE_FROM_ZITATEL_PAT="YOUR-PERSONAL-ACCESS-TOKEN"
```

Go to Organization, click on managers:
![Add Organization manager](assets/zitadel-service-user-pat-01.png)<br>
<br>
Add _zitadel-admin-sa_:
![Add zitadel-admin-sa as manager](assets/zitadel-service-user-pat-02.png)<br>
<br>
Set permissions for zitadel-admin-sa to Org Owner:
![Set Org Owner permission](assets/zitadel-service-user-pat-03.png)<br>

## Usage

Download the scripts to your NetBird directory where compose/config files are present.

```bash
curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-migrate-from-zitadel.sh -o netbird-migrate-from-zitadel.sh && chmod +x netbird-migrate-from-zitadel.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/create-zitadel-netbird-sso-project.sh -o create-zitadel-netbird-sso-project.sh && chmod +x create-zitadel-netbird-sso-project.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-migrate-rollback.sh -o netbird-migrate-rollback.sh && chmod +x netbird-migrate-rollback.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-legacy-update.sh -o netbird-legacy-update.sh && chmod +x netbird-legacy-update.sh

curl -fsSL https://github.com/ggfx/netbird-migrate-from-zitadel/raw/main/netbird-legacy-backup.sh -o netbird-legacy-backup.sh && chmod +x netbird-legacy-backup.sh
```

Run from your NetBird directory:

Dry-run (default):

```bash
sudo ./netbird-migrate-from-zitadel.sh
```

Apply migration:

```bash
sudo ./netbird-migrate-from-zitadel.sh --apply
```

### Optional parameters:

Force download latest migration binary:

```bash
sudo ./netbird-migrate-from-zitadel.sh --download
```

Apply + force download:

```bash
sudo ./netbird-migrate-from-zitadel.sh --apply --download
```

More details about the scripts can be found in [DOCS.md](DOCS.md).

## Tests

Was tested on two Installations running Netbird version 0.71.0 and 0.71.2, with and without Caddy, using Zitadel version 2.64.1.