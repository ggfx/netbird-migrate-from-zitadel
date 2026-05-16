#!/usr/bin/env bash
# What this script does:
# 1. Identifies the Docker volume used by the management server
# 2. Retrieves the host path of the volume
# 3. Restores the original store.db from the backup
# 4. Restores the original management.json from the backup

docker compose stop management

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Identify the volume name
VOLUME_NAME=$(docker volume ls --format '{{ .Name }}' | grep -Ei 'management|mgmt')
echo "Volume: $VOLUME_NAME"

# Get the host path
export NETBIRD_DATA_DIR=$(docker volume inspect "$VOLUME_NAME" --format '{{ .Mountpoint }}')
echo "Path: $NETBIRD_DATA_DIR"

# (SQLite only) Verify store.db.bak exists, then rollback to the original store.db from the backup
sudo ls "$NETBIRD_DATA_DIR/store.db.bak"
sudo cp "$NETBIRD_DATA_DIR/store.db.bak" "$NETBIRD_DATA_DIR/store.db"

# Verify management.json exists, the path will vary based on your setup, then rollback to the original management.json from the backup
export NETBIRD_CONFIG_PATH="$SCRIPT_DIR/management.json"
# cat "$NETBIRD_CONFIG_PATH"

cp "$NETBIRD_CONFIG_PATH.bak" "$NETBIRD_CONFIG_PATH"

# Verify dashboard.env exists, then rollback to the original dashboard.env from the backup
export DASHBOARD_ENV_PATH="$SCRIPT_DIR/dashboard.env"
cp "$DASHBOARD_ENV_PATH.bak" "$DASHBOARD_ENV_PATH"

docker compose up -d --force-recreate management dashboard