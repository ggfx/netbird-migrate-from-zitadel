#!/usr/bin/env bash
# What this script does:
# Create a legacy-backup folder with full-date (%+4Y-%m-%d) and time (%H:%M:%S) but only numbers and dashes, e.g., "legacy-backup-20240427-153045"
# Copy the following files to the backup folder: docker-compose.yml, zitadel.env, dashboard.env, turnserver.conf, management.json, relay.env, zdb.env
# Stop the management server container, copy the /var/lib/netbird/ directory from the management container to the backup folder, and then start the management server container again. This ensures that all data and configuration related to the management server is backed up before any migration or update actions are taken.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

backup_folder="$SCRIPT_DIR/legacy-backup-$(date +%Y%m%d-%H%M%S)"

if [ ! -d $backup_folder ];
then
    echo "Create Backup directory $backup_folder"
    mkdir $backup_folder
fi

echo "Copy files to backup directory"

cp -au docker-compose.yml zitadel.env dashboard.env turnserver.conf management.json relay.env zdb.env "$backup_folder/"
docker compose stop management
docker compose cp -a management:/var/lib/netbird/ "$backup_folder/"
docker compose start management

echo "Backup finished; Files copied to $backup_folder"
