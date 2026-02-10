#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  slides_relay_streamdeck_trigger.sh [relay_trigger_config_file]

Config variables:
  LOCAL_RUNNER            Path to slides_machine_runner.sh
  LOCAL_CONFIG            Local machine slides config path
  RUN_LOCAL=1             Run local machine automation immediately
  RUN_RELAY=1             Post trigger event to cloud relay
  RELAY_URL               Webhook relay URL
  RELAY_SECRET            Shared secret
  ACTION=refresh_slides   Relay action name
  SOURCE_LABEL            Identifier for this controller
  CURL_TIMEOUT_SECONDS=8  HTTP timeout
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="${1:-$PROJECT_ROOT/config/relay_streamdeck.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

LOCAL_RUNNER="${LOCAL_RUNNER:-$PROJECT_ROOT/scripts/slides_machine_runner.sh}"
LOCAL_CONFIG="${LOCAL_CONFIG:-$PROJECT_ROOT/config/local.env}"
RUN_LOCAL="${RUN_LOCAL:-1}"
RUN_RELAY="${RUN_RELAY:-1}"
RELAY_URL="${RELAY_URL:-}"
RELAY_SECRET="${RELAY_SECRET:-}"
ACTION="${ACTION:-refresh_slides}"
SOURCE_LABEL="${SOURCE_LABEL:-$(hostname)}"
CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-8}"

if [[ "$RUN_LOCAL" == "1" ]]; then
  echo "Running local slides automation..."
  "$LOCAL_RUNNER" "$LOCAL_CONFIG"
fi

if [[ "$RUN_RELAY" != "1" ]]; then
  exit 0
fi

if [[ -z "$RELAY_URL" ]]; then
  echo "RUN_RELAY=1 but RELAY_URL is empty." >&2
  exit 1
fi

if [[ -z "$RELAY_SECRET" ]]; then
  echo "RUN_RELAY=1 but RELAY_SECRET is empty." >&2
  exit 1
fi

if command -v uuidgen >/dev/null 2>&1; then
  event_id="$(uuidgen)"
else
  event_id="$(date +%s)-$RANDOM"
fi

requested_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
payload=$(printf '{"secret":"%s","eventId":"%s","action":"%s","source":"%s","requestedAt":"%s"}' \
  "$RELAY_SECRET" \
  "$event_id" \
  "$ACTION" \
  "$SOURCE_LABEL" \
  "$requested_at")

echo "Posting relay event $event_id to $RELAY_URL..."
response="$({
  curl -fsS \
    --connect-timeout "$CURL_TIMEOUT_SECONDS" \
    --max-time "$CURL_TIMEOUT_SECONDS" \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$RELAY_URL"
} 2>&1)"

echo "Relay response: $response"
