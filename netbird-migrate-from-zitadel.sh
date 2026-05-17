#!/usr/bin/env bash
# What this script does:
# 1. Fetches the latest release of the netbird-idp-migrate tool from GitHub
# 2. Prepares the OIDC provider configuration for Zitadel
# 3. Stops the management server
# 4. Backs up the existing management server data and configuration
# 5. Validates the migration with a dry-run
# 6. Optionally applies the migration changes if --apply is passed as an argument

# Use optional arguments:
# --apply: apply migration changes (default is dry-run)
# --download: download netbird-idp-migrate tarball from GitHub releases
DRY_RUN=1
DOWNLOAD=0

for arg in "$@"; do
  case "$arg" in
    --apply)
      DRY_RUN=0
      ;;
    --download)
      DOWNLOAD=1
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--apply] [--download]"
      exit 1
      ;;
  esac
done

# Function to set or update environment variables in a .env file.
set_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp

  [ -f "$env_file" ] || : > "$env_file"
  tmp="$(mktemp)"

  awk -v key="$key" -v value="$value" '
    BEGIN { updated=0 }
    # Match lines like:
    # KEY=...
    # export KEY=...
    $0 ~ "^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=" {
      print key "=" value
      updated=1
      next
    }
    { print }
    END {
      if (!updated) print key "=" value
    }
  ' "$env_file" > "$tmp" && mv "$tmp" "$env_file"
}

# Start this script as root to ensure we have the necessary permissions to access the management server data and configuration for backup and migration purposes.
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root to ensure proper permissions for backup and migration."
  exit 1
fi

# First check if this script is required to run. Check in docker compose if there is already a container name "netbird-server" then exit with a message that migration is not needed.
# This ensures that users do not run the migration tool unnecessarily if they are already on the latest version of Netbird.
if docker compose ps | grep -q "netbirdio/netbird-server"; then
  echo "Netbird Server container is already running. Migration from Zitadel is not needed."
  exit 0
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
OUTPUT_ENV="$SCRIPT_DIR/netbird-migrate-from-zitadel.env"
ZITADEL_ENV_FILE="$SCRIPT_DIR/zitadel.env"
DASHBOARD_ENV_FILE="$SCRIPT_DIR/dashboard.env"
CADDY_FILE="$SCRIPT_DIR/Caddyfile"

# Verify that we are in the correct directory by checking for the presence of dashboard.env and zitadel.env files.
# If these files are missing, exit with a message to run the script from the correct directory.
if [[ ! -f "$DASHBOARD_ENV_FILE" || ! -f "$ZITADEL_ENV_FILE" ]]; then
  echo "Please run this script from the directory where your dashboard.env and zitadel.env files are located."
  exit 1
fi

LATEST_TAG=$(curl -s https://api.github.com/repos/netbirdio/netbird/releases/latest | jq -r '.tag_name')
LATEST_V=${LATEST_TAG#*v}

# Get the domain from dashboard.env, find NETBIRD_MGMT_API_ENDPOINT and extract the domain part from the URL. This is needed to configure the OIDC provider for Zitadel.
DOMAIN=$(grep -Eo 'NETBIRD_MGMT_API_ENDPOINT=https?://[^/"]+' "$DASHBOARD_ENV_FILE" | awk -F[/:] '{print $4}')

# Read variables from zitadel.env, using ZITADEL_EXTERNALDOMAIN as the domain if it is set, otherwise fallback to the domain extracted from dashboard.env. This allows users to specify a different domain for Zitadel if needed.
source "$ZITADEL_ENV_FILE"
DOMAIN_Z=${ZITADEL_EXTERNALDOMAIN:-$DOMAIN}

# Stop the script if dashboard.env already contains https://$DOMAIN/oauth2"
if grep -q "https://$DOMAIN/oauth2" "$DASHBOARD_ENV_FILE"; then
  echo "Dashboard is already configured with the new OIDC provider. Migration from Zitadel may have already been applied."
  echo "With this script you can not re-apply the migration, because your backups will be overwritten and you may lose data. You need to rollback first."
  exit 1
fi

# Step 1. Update to the latest management server

# Check the currently installed version and if versions do not match exit with a message to update the management server first.
# This ensures that the migration tool is compatible with the management server version.
# Provide information what to do: run netbird-legacy-update.sh
INSTALLED_VERSION=$(docker compose exec management /go/bin/netbird-mgmt -v | awk '{print $NF}')
if [[ "${LATEST_TAG}" != "v${INSTALLED_VERSION}" ]]; then
  echo "Latest version is ${LATEST_TAG}, but you have ${INSTALLED_VERSION} installed."
  echo "Please update your legacy 5-container setup to the latest version before running this migration tool."
  echo "Use ./netbird-legacy-update.sh to update your legacy 5-container setup."
  exit 1
fi

# Step 2. Get the migration tool

# Download the official migration tool from GitHub releases, check if download is forced with --download flag or if the tool is still missing locally.
# This ensures that users have the latest version of the migration tool, which may include important bug fixes and improvements for the migration process.
if [[ $DOWNLOAD -eq 1 || ! -f "./netbird-idp-migrate" ]]; then
  echo "Getting release $LATEST_TAG with version $LATEST_V and running migration from Zitadel for $DOMAIN_Z"
  curl -L -o netbird-idp-migrate.tar.gz https://github.com/netbirdio/netbird/releases/download/$LATEST_TAG/netbird-idp-migrate_${LATEST_V}_linux_amd64.tar.gz
  tar xzf netbird-idp-migrate.tar.gz
  chmod +x netbird-idp-migrate
fi

# Step 3. Prepare your provider (Zitadel)

# Read CLIENT_ID and CLIENT_SECRET from netbird-migrate-from-zitadel.env, create file with empty keys, if it does not exist.
# This file is expected to be created by the user with the credentials from the Zitadel Web application.
# Stop early when netbird-migrate-from-zitadel.env file is missing or the web app credentials are not configured yet. Check for missing client_id or client_secret and exit with a message to set up a Zitadel Web application first.
if [[ ! -f "$OUTPUT_ENV" ]]; then
# Manual step required: Create a Personal Access Token
# Use the script create-zitadel-netbird-sso-project.sh to create a project and OIDC Web application for NetBird in your Zitadel instance.
# It will write the resulting client credentials to netbird-migrate-from-zitadel.env
# The script will also read the necessary configuration from your existing dashboard.env and zitadel.env files to set up the OIDC provider configuration correctly for the migration process.
# If there is any issue this scripts exits with an appropriate message to help you troubleshoot the configuration.
  if ! ./create-zitadel-netbird-sso-project.sh; then
    echo "Failed to create Zitadel project/application. Aborting migration."
    exit 1
  fi
fi
source "$OUTPUT_ENV"
if [[ -z "${CLIENT_ID:-}" || -z "${CLIENT_SECRET:-}" ]]; then
  if ! ./create-zitadel-netbird-sso-project.sh; then
    echo "Please set up a Zitadel Web application first and then fill in CLIENT_ID/CLIENT_SECRET in $OUTPUT_ENV."
    echo "You can use the create-zitadel-netbird-sso-project.sh script to create a project and OIDC Web application for NetBird in your Zitadel instance which will write the resulting client credentials to $OUTPUT_ENV."
    echo "If you want to manually create a Zitadel Web application for Netbird, you can follow the instructions in the documentation:"
    echo "https://docs.netbird.io/selfhosted/identity-providers/zitadel"
    echo "Console: https://$DOMAIN_Z/ui/console/"
    exit 1
  fi
fi

cat > connector.json <<EOF
{
  "type": "oidc",
  "name": "Zitadel",
  "id": "zitadel",
  "config": {
    "issuer": "https://$DOMAIN_Z",
    "clientID": "$CLIENT_ID",
    "clientSecret": "$CLIENT_SECRET"
  }
}
EOF

export NETBIRD_IDP_SEED_INFO=$(base64 < connector.json | tr -d '\n')

# Step 4. Stop manangement server

docker compose stop management

# Step 5. Backup data

# Identify the volume name
VOLUME_NAME=$(docker volume ls --format '{{ .Name }}' | grep -Ei 'management|mgmt')
echo "Volume: $VOLUME_NAME"

# Get the host path
export NETBIRD_DATA_DIR=$(docker volume inspect "$VOLUME_NAME" --format '{{ .Mountpoint }}')
echo "Path: $NETBIRD_DATA_DIR"

# Verify management.json exists, the path will vary based on your setup, then back up
export NETBIRD_CONFIG_PATH="$SCRIPT_DIR/management.json"
# cat "$NETBIRD_CONFIG_PATH"

# Verify dashboard.env exists, then make a back up
export DASHBOARD_ENV_PATH="$DASHBOARD_ENV_FILE"

if [[ $DRY_RUN -eq 0 ]]; then
  # (SQLite only) Verify store.db exists, then back up
  sudo ls "$NETBIRD_DATA_DIR/store.db"
  sudo cp "$NETBIRD_DATA_DIR/store.db" "$NETBIRD_DATA_DIR/store.db.bak"

  cp "$NETBIRD_CONFIG_PATH" "$NETBIRD_CONFIG_PATH.bak"

  cp "$DASHBOARD_ENV_PATH" "$DASHBOARD_ENV_PATH.bak"

  # Inform the user about the backups
  echo "Backups created:"
  echo "- SQLite database: $NETBIRD_DATA_DIR/store.db.bak"
  echo "- Management config: $NETBIRD_CONFIG_PATH.bak"
  echo "- Dashboard env: $DASHBOARD_ENV_PATH.bak"
  echo "Please keep these backup files safe. You will be able to rollback with netbird-migrate-rollback.sh if needed."
fi

# Step 6. Validate and dry-run

echo $NETBIRD_CONFIG_PATH
echo $NETBIRD_DATA_DIR
echo $NETBIRD_IDP_SEED_INFO | base64 -d

# This should match the same env var content that is passed to the management server
#export NB_STORE_ENGINE_POSTGRES_DSN="host=localhost port=5432 user=postgres password=postgres dbname=netbird sslmode=disable"

# first check with --dry-run to validate the migration without applying changes then exit the script before post-migration.
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Running in dry-run mode. No changes will be applied."
  ./netbird-idp-migrate --domain $DOMAIN_Z --dry-run

  docker compose start management
  echo "Dry-run completed. If the output looks good, run the script again with --apply to apply the migration changes."
  exit 0  
else
  echo "Running migration. Changes will be applied."
  ./netbird-idp-migrate --domain $DOMAIN_Z
fi

# Step 7. Post-migration

# Updating the dashboard.env with the new OIDC provider configuration and informing the user about the next steps to complete the migration process.
# Replace OIDC block in dashboard.env with the new OIDC provider configuration for Zitadel.
# This ensures that the dashboard is configured to use the new OIDC provider for authentication after the migration is complete.

set_env_var "$DASHBOARD_ENV_FILE" "AUTH_AUDIENCE" "netbird-dashboard"
set_env_var "$DASHBOARD_ENV_FILE" "AUTH_CLIENT_ID" "netbird-dashboard"
set_env_var "$DASHBOARD_ENV_FILE" "AUTH_AUTHORITY" "https://$DOMAIN/oauth2"
set_env_var "$DASHBOARD_ENV_FILE" "AUTH_SUPPORTED_SCOPES" "openid profile email groups"
set_env_var "$DASHBOARD_ENV_FILE" "AUTH_REDIRECT_URI" "/nb-auth"
set_env_var "$DASHBOARD_ENV_FILE" "AUTH_SILENT_REDIRECT_URI" "/nb-silent-auth"

# Finally start the management and dahboard containers again to apply the new configuration and complete the migration process.
docker compose up -d --force-recreate management dashboard

# Check wether Caddy is running in the docker-compose setup then update the local Caddyfile.
# Find reverse_proxy /api/* management:80 in Caddyfile and insert reverse_proxy /oauth2/* management:80 below it.
# Restart caddy to apply the changes.
if docker compose ps | grep -q "caddy" && ! grep -q "reverse_proxy /oauth2/\* management:80" "$CADDY_FILE"; then
  API_PROXY_LINE=$(grep -n "reverse_proxy /api/\* management:80" "$CADDY_FILE" | head -n1 | cut -d: -f1)
  if [[ -n "$API_PROXY_LINE" ]]; then
    sed -i "${API_PROXY_LINE}a\\
    reverse_proxy /oauth2/* management:80" "$CADDY_FILE"
    docker compose restart caddy
    # Verify route
    if curl -s https://$DOMAIN/oauth2/.well-known/openid-configuration | head -5; then
      echo "OIDC configuration is available at https://$DOMAIN/oauth2/.well-known/openid-configuration"
    else
      echo "Failed to verify OIDC configuration at https://$DOMAIN/oauth2/.well-known/openid-configuration"
      echo "Please check if oauth2 route is correctly configured in your Caddyfile and that the management server is running properly."
    fi
    echo ============================================================
    echo "Migration completed."
  else
    # Inform the user about the next steps to complete the migration process, which include updating the Webserver to route /oauth2/* to the management server for OIDC authentication and verifying the OIDC configuration with a curl command.
    echo ============================================================
    echo "Migration completed. Please update your Webserver to route /oauth2/* to the management server for OIDC authentication."
    echo Place "reverse_proxy /oauth2/* management:80" alongside /api/* into your Webserver configuration.
    echo Then restart your webserver to apply the changes.
    echo Verify route: curl -s https://$DOMAIN/oauth2/.well-known/openid-configuration | head -5
    echo You should see the new oauth2 configuration for your Dex-IdP with the correct issuer URL.
  fi
fi

echo If there are any issues please check the migration guide at https://docs.netbird.io/selfhosted/migration/external-to-embedded-idp#troubleshooting
echo At any point, you can rollback with netbird-migrate-rollback.sh using the backup files created in this migration process.

# Inform the user about possibility to upgrade to combined server setup.
echo ============================================================
echo "If you want to upgrade to the combined server setup now, you can do so. Please check the migration guide for the next steps:"
echo "https://docs.netbird.io/selfhosted/migration/combined-container"