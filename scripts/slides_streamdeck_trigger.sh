#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  slides_streamdeck_trigger.sh [controller_config_file]

Controller config variables:
  LOCAL_RUNNER            Path to slides_machine_runner.sh
  LOCAL_CONFIG            Local machine config path
  RUN_LOCAL=1             Run local machine automation
  RUN_REMOTE=1            Run remote machine automation
  REMOTE_SSH_TARGET       SSH target (e.g., user@10.2.130.61)
  REMOTE_RUNNER           Runner path on remote machine
  REMOTE_CONFIG           Config path on remote machine
  SSH_TIMEOUT_SECONDS=6   SSH connection timeout
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONTROLLER_CONFIG="${1:-$PROJECT_ROOT/config/controller.env}"
if [[ -f "$CONTROLLER_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONTROLLER_CONFIG"
fi

LOCAL_RUNNER="${LOCAL_RUNNER:-$PROJECT_ROOT/scripts/slides_machine_runner.sh}"
LOCAL_CONFIG="${LOCAL_CONFIG:-$PROJECT_ROOT/config/local.env}"
RUN_LOCAL="${RUN_LOCAL:-1}"
RUN_REMOTE="${RUN_REMOTE:-1}"
SSH_TIMEOUT_SECONDS="${SSH_TIMEOUT_SECONDS:-6}"

REMOTE_SSH_TARGET="${REMOTE_SSH_TARGET:-}"
REMOTE_RUNNER="${REMOTE_RUNNER:-$LOCAL_RUNNER}"
REMOTE_CONFIG="${REMOTE_CONFIG:-$PROJECT_ROOT/config/remote.env}"

if [[ "$RUN_LOCAL" == "1" ]]; then
  echo "Running local slides automation..."
  "$LOCAL_RUNNER" "$LOCAL_CONFIG"
fi

if [[ "$RUN_REMOTE" != "1" ]]; then
  exit 0
fi

if [[ -z "$REMOTE_SSH_TARGET" ]]; then
  echo "RUN_REMOTE=1 but REMOTE_SSH_TARGET is empty." >&2
  exit 1
fi

remote_cmd=$(printf '%q %q' "$REMOTE_RUNNER" "$REMOTE_CONFIG")

echo "Running remote slides automation on $REMOTE_SSH_TARGET..."
ssh \
  -o BatchMode=yes \
  -o ConnectTimeout="$SSH_TIMEOUT_SECONDS" \
  "$REMOTE_SSH_TARGET" \
  "$remote_cmd"
