#!/usr/bin/env bash
# Creates a Zitadel project and OIDC Web application for NetBird and writes the resulting client credentials to netbird-migrate-from-zitadel.env.
# If the project already exists, it will use the existing project.
# If the OIDC Web application already exists, the script will exit with an error to avoid accidentally overwriting the existing application's client secret.
# Usually the APP_NAME will be randomized with a timestamp to avoid conflicts

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
OUTPUT_ENV="$SCRIPT_DIR/netbird-migrate-from-zitadel.env"
ZITADEL_ENV_FILE="$SCRIPT_DIR/zitadel.env"
DASHBOARD_ENV_FILE="$SCRIPT_DIR/dashboard.env"
NETBIRD_MGMT_API_ENDPOINT=$(grep -Eo 'NETBIRD_MGMT_API_ENDPOINT=https?://[^/"]+' "$DASHBOARD_ENV_FILE" | awk -F[=] '{print $2}')

PROJECT_NAME="Netbird SSO"
APP_NAME="Netbird SSO $(date +%s)"
REDIRECT_URI="$NETBIRD_MGMT_API_ENDPOINT/oauth2/callback"

usage() {
  cat <<EOF
Usage: $0 --redirect-uri <netbird_callback_url> [--project-name <name>] [--app-name <name>]

Required:
  --redirect-uri   Netbird callback URL copied from Settings -> Identity Providers.

Optional:
  --project-name   Zitadel project name (default: Netbird SSO)
  --app-name       Zitadel application name (default: Netbird SSO <epoch_timestamp>)

Input requirements from zitadel.env and netbird-migrate-from-zitadel.env:
  ZITADEL_EXTERNALDOMAIN=<your-zitadel-domain>
  MIGRATE_FROM_ZITATEL_PAT=<your-zitadel-personal-access-token>

Output:
  $OUTPUT_ENV
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --redirect-uri)
      REDIRECT_URI="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="${2:-}"
      shift 2
      ;;
    --app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REDIRECT_URI" ]]; then
  echo "Missing required argument: --redirect-uri"
  usage
  exit 1
fi

if [[ ! -f "$OUTPUT_ENV" ]]; then
  cat > "$OUTPUT_ENV" <<EOF
MIGRATE_FROM_ZITATEL_PAT=""
EOF
  echo "Created $OUTPUT_ENV template."
  echo "Please create a Personal Access Token (PAT) and set the value of MIGRATE_FROM_ZITATEL_PAT='' in $OUTPUT_ENV."
  exit 1
fi

source "$ZITADEL_ENV_FILE"
source "$OUTPUT_ENV"

if [[ -z "${ZITADEL_EXTERNALDOMAIN:-}" || -z "${MIGRATE_FROM_ZITATEL_PAT:-}" ]]; then
  echo "Please set ZITADEL_EXTERNALDOMAIN in $ZITADEL_ENV_FILE and MIGRATE_FROM_ZITATEL_PAT in $OUTPUT_ENV"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found. Install jq and re-run."
  exit 1
fi

BASE_URL="https://${ZITADEL_EXTERNALDOMAIN}"

api_call() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local tmp
  local http_code

  tmp=$(mktemp)

  if [[ -n "$body" ]]; then
    http_code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "${BASE_URL}${path}" \
      -H "Authorization: Bearer ${MIGRATE_FROM_ZITATEL_PAT}" \
      -H "Content-Type: application/json" \
      -d "$body")
  else
    http_code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "${BASE_URL}${path}" \
      -H "Authorization: Bearer ${MIGRATE_FROM_ZITATEL_PAT}" \
      -H "Content-Type: application/json")
  fi

  # If the API call returns an error status code (4xx or 5xx) but the response body contains "No changes (COMMAND-", treat it as a non-error since it just means the configuration is already correct and no update was needed.
  # If the API call returns an error with message "Application already exists", this means an application with the same name already exists in the project, so exit with an error to avoid accidentally overwriting the existing application's client secret, since that would break any existing integrations using that application.
  # The user should then delete the existing application or choose a different name for the new application using the --app-name argument when running the script.
  # Otherwise, if there is an error status code without that message, print the error and exit.
  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    if grep -q "No changes (COMMAND-" "$tmp"; then
      echo "No changes needed for ${method} ${path}"
    elif grep -q "Application already exists" "$tmp"; then
      echo "Error: An application with the same name already exists in the project. Please delete the existing application or choose a different name for the new application using the --app-name argument when running the script." >&2
      cat "$tmp" >&2
      rm -f "$tmp"
      exit 1
    else
      echo "Zitadel API error: ${method} ${path} returned HTTP ${http_code}" >&2
      cat "$tmp" >&2
      rm -f "$tmp"
      exit 1
    fi
  fi

  cat "$tmp"
  rm -f "$tmp"
}

echo "Validating PAT against Zitadel API..."
api_call "GET" "/auth/v1/users/me" >/dev/null

echo "Checking for existing project named '${PROJECT_NAME}'..."
search_payload=$(jq -n --arg q "$PROJECT_NAME" '{query: {offset: "0", limit: 50, asc: true}, queries: [{nameQuery: {name: $q, method: "TEXT_QUERY_METHOD_EQUALS_IGNORE_CASE"}}]}')
projects_json=$(api_call "POST" "/management/v1/projects/_search" "$search_payload")
PROJECT_ID=$(echo "$projects_json" | jq -r '.result[]? | select(.name == "'"$PROJECT_NAME"'") | .id' | head -n1)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "Creating project '${PROJECT_NAME}'..."
  create_project_payload=$(jq -n --arg name "$PROJECT_NAME" '{name: $name}')
  project_response=$(api_call "POST" "/management/v1/projects" "$create_project_payload")
  PROJECT_ID=$(echo "$project_response" | jq -r '.id')
  if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
    echo "Failed to parse project id from Zitadel response."
    exit 1
  fi
else
  echo "Using existing project id: ${PROJECT_ID}"
fi

echo "Creating OIDC Web application '${APP_NAME}'..."
create_app_payload=$(jq -n \
  --arg name "$APP_NAME" \
  --arg redirect "$REDIRECT_URI" \
  '{
    name: $name,
    redirectUris: [$redirect],
    responseTypes: ["OIDC_RESPONSE_TYPE_CODE"],
    grantTypes: ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"],
    appType: "OIDC_APP_TYPE_WEB",
    authMethodType: "OIDC_AUTH_METHOD_TYPE_BASIC",
    version: "OIDC_VERSION_1_0",
    devMode: false,
    accessTokenType: "OIDC_TOKEN_TYPE_BEARER",
    idTokenRoleAssertion: true,
    idTokenUserinfoAssertion: true
  }')

app_response=$(api_call "POST" "/management/v1/projects/${PROJECT_ID}/apps/oidc" "$create_app_payload")

APP_ID=$(echo "$app_response" | jq -r '.appId')
CLIENT_ID=$(echo "$app_response" | jq -r '.clientId')
CLIENT_SECRET=$(echo "$app_response" | jq -r '.clientSecret')

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  echo "Failed to parse app id from Zitadel response."
  exit 1
fi

if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "null" || -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
  echo "Failed to parse client credentials from Zitadel response."
  echo "Raw app response:"
  echo "$app_response"
  exit 1
fi

# Ensure token assertion flags are explicitly set on config as in the guide.
# This seems to throw an error like HTTP 400: {"code":9,"message":"No changes (COMMAND-1m88i)",...} so maybe not needed, but we want to be sure these are set correctly for NetBird.
update_app_payload=$(jq -n \
  --arg redirect "$REDIRECT_URI" \
  '{
    redirectUris: [$redirect],
    responseTypes: ["OIDC_RESPONSE_TYPE_CODE"],
    grantTypes: ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"],
    appType: "OIDC_APP_TYPE_WEB",
    authMethodType: "OIDC_AUTH_METHOD_TYPE_BASIC",
    devMode: false,
    accessTokenType: "OIDC_TOKEN_TYPE_BEARER",
    idTokenRoleAssertion: true,
    idTokenUserinfoAssertion: true
  }')

api_call "PUT" "/management/v1/projects/${PROJECT_ID}/apps/${APP_ID}/oidc_config" "$update_app_payload"

# Append to the output env file instead of overwriting it, in case there are other variables the user wants to set in there.
# If CLIENT_ID and CLIENT_SECRET already exist in the file, try to replace them with the new values, otherwise append them to the end of the file.
if grep -q "CLIENT_ID=" "$OUTPUT_ENV"; then
  sed -i "s/CLIENT_ID=.*/CLIENT_ID=\"${CLIENT_ID}\"/" "$OUTPUT_ENV"
else
  echo "CLIENT_ID=\"${CLIENT_ID}\"" >> "$OUTPUT_ENV"
fi
if grep -q "CLIENT_SECRET=" "$OUTPUT_ENV"; then
  sed -i "s/CLIENT_SECRET=.*/CLIENT_SECRET=\"${CLIENT_SECRET}\"/" "$OUTPUT_ENV"
else
  echo "CLIENT_SECRET=\"${CLIENT_SECRET}\"" >> "$OUTPUT_ENV"
fi

chmod 600 "$OUTPUT_ENV" || true

echo "Success: Zitadel project and application are configured for NetBird."
echo "Credentials written to: $OUTPUT_ENV"

