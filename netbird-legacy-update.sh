#!/usr/bin/env bash
# What this script does:
# 1. Checks the currently installed version of the management server and compares it with the latest release version from GitHub. If versions do not match, exits with a message to update the management server first.
# 2. If the management server is not up to date, runs the netbird-legacy-backup.sh script. Then pulls the latest images for the management server and its dependencies, and restarts the containers to apply the updates.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd $SCRIPT_DIR
if [ -e docker-compose.yml ]
then
    if ! command -v jq >/dev/null 2>&1
    then
      apt-get -y install jq
    fi
    INSTALLED_VERSION=$(docker compose exec management /go/bin/netbird-mgmt -v | awk '{print $NF}')
    LATEST_TAG=$(curl -s https://api.github.com/repos/netbirdio/netbird/releases/latest | jq -r '.tag_name')
    echo -e "\n============================================================"
    if [[ "${LATEST_TAG}" == "v${INSTALLED_VERSION}" ]]; then
      echo "You already have the latest version ${INSTALLED_VERSION}."
    else
      ./netbird-legacy-backup.sh
      docker compose down
      docker pull netbirdio/dashboard:latest
      docker pull netbirdio/signal:latest
      docker pull netbirdio/relay:latest
      docker pull netbirdio/management:latest
      docker pull coturn/coturn
      docker pull postgres:16-alpine
      docker compose up -d
      echo -e "\nNetbird v${INSTALLED_VERSION} has been updated to ${LATEST_TAG}."
    fi
    echo -e "============================================================\n"
else
    echo -e "\n============================================================"
    echo "Something is not right, is Netbird already installed?"
    echo "The docker-compose.yml file is missing in your directory $SCRIPT_DIR."
    echo -e "============================================================\n"
fi
