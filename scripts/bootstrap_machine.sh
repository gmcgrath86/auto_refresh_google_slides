#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bootstrap_machine.sh [--role presentation|relay-agent|controller|all]

Roles:
  presentation  Create config/local.env if missing and prep local runner.
  relay-agent   Create config/relay_agent.env if missing.
  controller    Create controller trigger configs if missing.
  all           Prepare all local config files (default).
USAGE
}

ROLE="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="${2:-}"
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
CONFIG_DIR="$PROJECT_ROOT/config"

create_if_missing() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "Created: $dst"
  else
    echo "Exists:  $dst"
  fi
}

chmod +x "$PROJECT_ROOT"/scripts/*.sh

echo "Bootstrap role: $ROLE"

case "$ROLE" in
  presentation)
    create_if_missing "$CONFIG_DIR/local.env.example" "$CONFIG_DIR/local.env"
    ;;
  relay-agent)
    create_if_missing "$CONFIG_DIR/local.env.example" "$CONFIG_DIR/local.env"
    create_if_missing "$CONFIG_DIR/relay_agent.env.example" "$CONFIG_DIR/relay_agent.env"
    ;;
  controller)
    create_if_missing "$CONFIG_DIR/relay_streamdeck.env.example" "$CONFIG_DIR/relay_streamdeck.env"
    create_if_missing "$CONFIG_DIR/controller.env.example" "$CONFIG_DIR/controller.env"
    ;;
  all)
    create_if_missing "$CONFIG_DIR/local.env.example" "$CONFIG_DIR/local.env"
    create_if_missing "$CONFIG_DIR/relay_agent.env.example" "$CONFIG_DIR/relay_agent.env"
    create_if_missing "$CONFIG_DIR/relay_streamdeck.env.example" "$CONFIG_DIR/relay_streamdeck.env"
    create_if_missing "$CONFIG_DIR/controller.env.example" "$CONFIG_DIR/controller.env"
    ;;
  *)
    echo "Invalid role: $ROLE" >&2
    exit 1
    ;;
esac

echo "Done. Next: edit config files for this machine, then run the matching script from README/DEPLOY.md."
