#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  slides_relay_agent.sh [relay_agent_config_file]

Config variables:
  RELAY_URL               Webhook relay URL
  RELAY_SECRET            Shared secret
  RUNNER_PATH             Path to slides_machine_runner.sh
  RUNNER_CONFIG           Path to local slides config
  POLL_SECONDS=2          Poll interval
  CURL_TIMEOUT_SECONDS=8  HTTP timeout
  STATE_DIR               Directory for last seen event state
  STATE_FILE              State file path (optional override)
  ACTION_FILTER           Only run matching action (default: refresh_slides)
  FIRE_ON_STARTUP=0       0 = ignore current event when first started
  ACK_ON_FAILURE=1        1 = mark event as seen if runner fails
  VERBOSE=1               1 = print logs
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="${1:-$PROJECT_ROOT/config/relay_agent.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RELAY_URL="${RELAY_URL:-}"
RELAY_SECRET="${RELAY_SECRET:-}"
RUNNER_PATH="${RUNNER_PATH:-$PROJECT_ROOT/scripts/slides_machine_runner.sh}"
RUNNER_CONFIG="${RUNNER_CONFIG:-$PROJECT_ROOT/config/local.env}"
POLL_SECONDS="${POLL_SECONDS:-2}"
CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-8}"
STATE_DIR="${STATE_DIR:-$HOME/.codex-slides-relay}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/last_event_id}"
ACTION_FILTER="${ACTION_FILTER:-refresh_slides}"
FIRE_ON_STARTUP="${FIRE_ON_STARTUP:-0}"
ACK_ON_FAILURE="${ACK_ON_FAILURE:-1}"
VERBOSE="${VERBOSE:-1}"

if [[ -z "$RELAY_URL" ]]; then
  echo "RELAY_URL is required." >&2
  exit 1
fi

if [[ -z "$RELAY_SECRET" ]]; then
  echo "RELAY_SECRET is required." >&2
  exit 1
fi

if [[ ! -x "$RUNNER_PATH" ]]; then
  echo "Runner not executable: $RUNNER_PATH" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

log() {
  if [[ "$VERBOSE" == "1" ]]; then
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
  fi
}

extract_json_field() {
  local json="$1"
  local key="$2"

  printf '%s' "$json" | sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p"
}

fetch_event_json() {
  curl -fsS \
    --connect-timeout "$CURL_TIMEOUT_SECONDS" \
    --max-time "$CURL_TIMEOUT_SECONDS" \
    --get \
    --data-urlencode "secret=${RELAY_SECRET}" \
    "$RELAY_URL"
}

read_last_event_id() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
    return 0
  fi

  printf ''
}

write_last_event_id() {
  local event_id="$1"
  printf '%s\n' "$event_id" > "$STATE_FILE"
}

prime_state_file() {
  if [[ -f "$STATE_FILE" ]]; then
    return 0
  fi

  if [[ "$FIRE_ON_STARTUP" == "1" ]]; then
    write_last_event_id ""
    return 0
  fi

  local bootstrap_json bootstrap_event_id
  bootstrap_json="$(fetch_event_json || true)"
  bootstrap_event_id="$(extract_json_field "$bootstrap_json" "eventId")"
  write_last_event_id "$bootstrap_event_id"

  if [[ -n "$bootstrap_event_id" ]]; then
    log "Initialized state with current relay event: $bootstrap_event_id"
  fi
}

run_local_action() {
  local action="$1"
  local event_id="$2"

  if [[ -n "$ACTION_FILTER" && "$action" != "$ACTION_FILTER" ]]; then
    log "Ignoring event $event_id with action '$action' (filter: '$ACTION_FILTER')."
    return 0
  fi

  log "Executing runner for event $event_id (action: $action)."
  "$RUNNER_PATH" "$RUNNER_CONFIG"
}

prime_state_file

log "Relay agent started. Poll interval: ${POLL_SECONDS}s"

while true; do
  json="$(fetch_event_json || true)"

  if [[ -z "$json" ]]; then
    log "Relay fetch failed; retrying."
    sleep "$POLL_SECONDS"
    continue
  fi

  event_id="$(extract_json_field "$json" "eventId")"
  action="$(extract_json_field "$json" "action")"

  if [[ -z "$event_id" ]]; then
    sleep "$POLL_SECONDS"
    continue
  fi

  last_event_id="$(read_last_event_id)"

  if [[ "$event_id" == "$last_event_id" ]]; then
    sleep "$POLL_SECONDS"
    continue
  fi

  if run_local_action "$action" "$event_id"; then
    write_last_event_id "$event_id"
    log "Event $event_id processed."
  else
    log "Runner failed for event $event_id."
    if [[ "$ACK_ON_FAILURE" == "1" ]]; then
      write_last_event_id "$event_id"
      log "Event $event_id marked as seen due to ACK_ON_FAILURE=1."
    fi
  fi

  sleep "$POLL_SECONDS"
done
