#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  slides_hotkey_trigger.sh [--mode local|relay|ssh] [--config path] [--slides-url url]

Modes:
  local  -> runs scripts/slides_machine_runner.sh with config/local.env
  relay  -> runs scripts/slides_relay_streamdeck_trigger.sh with config/relay_streamdeck.env
  ssh    -> runs scripts/slides_streamdeck_trigger.sh with config/controller.env

Options:
  --mode MODE       Trigger mode (default: local)
  --config PATH     Override config path for selected mode
  --slides-url URL  Local mode only: temporarily load this deck URL for one run
  -h, --help        Show this help

Environment:
  LOG_FILE          Log file path (default: /tmp/slides-hotkey.log)
  LOCK_DIR          Lock directory path (default: /tmp/slides-hotkey.lock)
USAGE
}

MODE="local"
CONFIG_PATH=""
SLIDES_URL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --slides-url)
      SLIDES_URL_OVERRIDE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$MODE" in
  local)
    RUNNER_PATH="$PROJECT_ROOT/scripts/slides_machine_runner.sh"
    DEFAULT_CONFIG="$PROJECT_ROOT/config/local.env"
    ;;
  relay)
    RUNNER_PATH="$PROJECT_ROOT/scripts/slides_relay_streamdeck_trigger.sh"
    DEFAULT_CONFIG="$PROJECT_ROOT/config/relay_streamdeck.env"
    ;;
  ssh)
    RUNNER_PATH="$PROJECT_ROOT/scripts/slides_streamdeck_trigger.sh"
    DEFAULT_CONFIG="$PROJECT_ROOT/config/controller.env"
    ;;
  *)
    echo "Invalid mode: $MODE (expected: local, relay, ssh)" >&2
    exit 1
    ;;
esac

if [[ -z "$CONFIG_PATH" ]]; then
  CONFIG_PATH="$DEFAULT_CONFIG"
fi

LOG_FILE="${LOG_FILE:-/tmp/slides-hotkey.log}"
LOCK_DIR="${LOCK_DIR:-/tmp/slides-hotkey.lock}"
RUN_CONFIG_PATH="$CONFIG_PATH"
TEMP_CONFIG_PATH=""

shell_quote_value() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  printf '"%s"' "$input"
}

build_one_shot_local_config() {
  local slides_url="$1"

  if [[ "$MODE" != "local" ]]; then
    echo "--slides-url is only supported with --mode local" >&2
    exit 1
  fi
  if [[ "$slides_url" != http://* && "$slides_url" != https://* ]]; then
    echo "--slides-url must be an http(s) URL" >&2
    exit 1
  fi

  TEMP_CONFIG_PATH="$(mktemp "${TMPDIR:-/tmp}/slides-load-config.XXXXXX")"
  cp "$CONFIG_PATH" "$TEMP_CONFIG_PATH"
  {
    printf '\n# One-shot deck load overrides\n'
    printf 'SLIDES_SOURCE_URL=%s\n' "$(shell_quote_value "$slides_url")"
    printf 'SLIDES_PRESENT_URL=""\n'
    printf 'SLIDES_NOTES_URL=""\n'
    printf 'AUTO_CAPTURE_FRONT_TAB=0\n'
    printf 'RESTORE_PREVIOUS_SLIDE_ON_REFRESH=0\n'
    printf 'FORCE_SLIDE_NUMBER_ON_LAUNCH=1\n'
  } >>"$TEMP_CONFIG_PATH"
  RUN_CONFIG_PATH="$TEMP_CONFIG_PATH"
}

if [[ -n "$SLIDES_URL_OVERRIDE" ]]; then
  build_one_shot_local_config "$SLIDES_URL_OVERRIDE"
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf '[%s] trigger ignored: previous run still active\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG_FILE"
  exit 0
fi

cleanup() {
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
  if [[ -n "$TEMP_CONFIG_PATH" ]]; then
    rm -f "$TEMP_CONFIG_PATH"
  fi
}
trap cleanup EXIT

{
  printf '\n[%s] trigger start mode=%s config=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$RUN_CONFIG_PATH"
  if [[ ! -x "$RUNNER_PATH" ]]; then
    echo "runner is not executable: $RUNNER_PATH"
    exit 1
  fi

  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "config file not found: $CONFIG_PATH"
    exit 1
  fi

  "$RUNNER_PATH" "$RUN_CONFIG_PATH"
  echo "trigger complete"
} >>"$LOG_FILE" 2>&1
