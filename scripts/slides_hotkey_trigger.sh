#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  slides_hotkey_trigger.sh [--mode local|relay|ssh] [--config path]

Modes:
  local  -> runs scripts/slides_machine_runner.sh with config/local.env
  relay  -> runs scripts/slides_relay_streamdeck_trigger.sh with config/relay_streamdeck.env
  ssh    -> runs scripts/slides_streamdeck_trigger.sh with config/controller.env

Options:
  --mode MODE       Trigger mode (default: local)
  --config PATH     Override config path for selected mode
  -h, --help        Show this help

Environment:
  LOG_FILE          Log file path (default: /tmp/slides-hotkey.log)
  LOCK_DIR          Lock directory path (default: /tmp/slides-hotkey.lock)
USAGE
}

MODE="local"
CONFIG_PATH=""

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

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf '[%s] trigger ignored: previous run still active\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG_FILE"
  exit 0
fi

cleanup() {
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

{
  printf '\n[%s] trigger start mode=%s config=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$CONFIG_PATH"
  if [[ ! -x "$RUNNER_PATH" ]]; then
    echo "runner is not executable: $RUNNER_PATH"
    exit 1
  fi

  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "config file not found: $CONFIG_PATH"
    exit 1
  fi

  "$RUNNER_PATH" "$CONFIG_PATH"
  echo "trigger complete"
} >>"$LOG_FILE" 2>&1
