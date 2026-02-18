#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  one_shot_remote_setup.sh [options]

Modes:
  --mode relay|local          Setup machine (default: relay).

Required for relay mode:
  --slides-url URL             Google Slides URL (edit or present URL)
  --relay-url URL              Google Apps Script relay /exec URL
  --relay-secret SECRET        Shared relay secret

Common options:
  --repo-dir PATH              Default: /Users/openai/auto_refresh_google_slides
  --repo-url URL               Default: https://github.com/gmcgrath86/auto_refresh_google_slides.git
  --no-health                  Skip relay health checks
  --no-hotkey                  Skip Hammerspoon hotkey setup
  --hotkey-mods CSV            Default: ctrl,alt,cmd
  --hotkey-key KEY             Default: r
  -h, --help

Examples:
  one_shot_remote_setup.sh \
    --mode relay \
    --slides-url "https://docs.google.com/presentation/d/.../edit" \
    --relay-url "https://script.google.com/macros/s/.../exec" \
    --relay-secret "supersecret"
USAGE
}

MODE="relay"
REPO_DIR="$HOME/auto_refresh_google_slides"
REPO_URL="https://github.com/gmcgrath86/auto_refresh_google_slides.git"
SLIDES_SOURCE_URL=""
RELAY_URL=""
RELAY_SECRET=""
INSTALL_HOTKEY=1
RUN_HEALTH=1
HOTKEY_MODS="ctrl,alt,cmd"
HOTKEY_KEY="r"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --slides-url)
      SLIDES_SOURCE_URL="${2:-}"
      shift 2
      ;;
    --relay-url)
      RELAY_URL="${2:-}"
      shift 2
      ;;
    --relay-secret)
      RELAY_SECRET="${2:-}"
      shift 2
      ;;
    --no-health)
      RUN_HEALTH=0
      shift
      ;;
    --no-hotkey)
      INSTALL_HOTKEY=0
      shift
      ;;
    --hotkey-mods)
      HOTKEY_MODS="${2:-}"
      shift 2
      ;;
    --hotkey-key)
      HOTKEY_KEY="${2:-}"
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

if [[ "$MODE" != "relay" && "$MODE" != "local" ]]; then
  echo "Invalid --mode '$MODE' (expected relay or local)." >&2
  exit 1
fi

if [[ "$MODE" == "relay" ]]; then
  if [[ -z "$RELAY_URL" || -z "$RELAY_SECRET" || -z "$SLIDES_SOURCE_URL" ]]; then
    echo "Relay mode requires --slides-url, --relay-url, and --relay-secret." >&2
    exit 1
  fi
fi

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

get_env_value() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    index($0, key "=") == 1 {
      val = substr($0, length(key) + 2)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^"|"$/, "", val)
      print val
      exit
    }
  ' "$file"
}

is_placeholder() {
  local value="$1"
  [[ -z "$value" || "$value" == *REPLACE_WITH* || "$value" == *replace-with* ]]
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [[ -f "$file" ]] && grep -q "^${key}=" "$file"; then
    local tmp
    tmp="$(mktemp)"
    /usr/bin/awk -v key="$key" -v value="$value" '
      index($0, key "=") == 1 { print key "=\"" value "\""; next }
      { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

cleanup() {
  local exit_code=$?

  if [[ -n "${AGENT_PID:-}" ]] && kill -0 "$AGENT_PID" >/dev/null 2>&1; then
    kill "$AGENT_PID" >/dev/null 2>&1 || true
    wait "$AGENT_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    log "Setup failed (exit=$exit_code)." >&2
  fi
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd git
require_cmd curl
require_cmd awk

REPO_DIR="${REPO_DIR%/}"
WORKDIR_REPO="$REPO_DIR"

if [[ -d "$WORKDIR_REPO/.git" ]]; then
  log "Updating repo at $WORKDIR_REPO"
  git -C "$WORKDIR_REPO" fetch --all --tags
  git -C "$WORKDIR_REPO" pull --ff-only --tags
else
  log "Cloning repo to $WORKDIR_REPO"
  mkdir -p "$WORKDIR_REPO"
  git clone "$REPO_URL" "$WORKDIR_REPO"
fi

SCRIPT_DIR="$WORKDIR_REPO/scripts"
BOOTSTRAP="$SCRIPT_DIR/bootstrap_machine.sh"
PROJECT_ROOT="$WORKDIR_REPO"
LOCAL_ENV="$PROJECT_ROOT/config/local.env"
RELAY_AGENT_ENV="$PROJECT_ROOT/config/relay_agent.env"
RELAY_STREAM_ENV="$PROJECT_ROOT/config/relay_streamdeck.env"
STATE_DIR="$HOME/.codex-slides-relay"

mkdir -p "$STATE_DIR"

"$BOOTSTRAP" --role presentation
if [[ "$MODE" == "relay" ]]; then
  "$BOOTSTRAP" --role relay-agent
fi

if [[ "$INSTALL_HOTKEY" == "1" ]]; then
  if [[ "$MODE" == "relay" ]]; then
    "$BOOTSTRAP" --role presentation --install-hotkey --hotkey-mode relay --hotkey-mods "$HOTKEY_MODS" --hotkey-key "$HOTKEY_KEY"
  else
    "$BOOTSTRAP" --role presentation --install-hotkey --hotkey-mode local --hotkey-mods "$HOTKEY_MODS" --hotkey-key "$HOTKEY_KEY"
  fi
fi

set_env_value "$LOCAL_ENV" "AUTO_CAPTURE_FRONT_TAB" "1"
set_env_value "$LOCAL_ENV" "BOUNDS_MODE" "auto"
set_env_value "$LOCAL_ENV" "DISPLAY_ASSIGNMENT" "slides:rightmost,notes:leftmost"
set_env_value "$LOCAL_ENV" "NOTES_PLUS_METHOD" "auto"

if [[ -n "$SLIDES_SOURCE_URL" ]]; then
  set_env_value "$LOCAL_ENV" "SLIDES_SOURCE_URL" "$SLIDES_SOURCE_URL"
fi

if [[ "$MODE" == "relay" ]]; then
  set_env_value "$RELAY_AGENT_ENV" "RELAY_URL" "$RELAY_URL"
  set_env_value "$RELAY_AGENT_ENV" "RELAY_SECRET" "$RELAY_SECRET"
  set_env_value "$RELAY_AGENT_ENV" "RUNNER_PATH" "$PROJECT_ROOT/scripts/slides_machine_runner.sh"
  set_env_value "$RELAY_AGENT_ENV" "RUNNER_CONFIG" "$LOCAL_ENV"
  set_env_value "$RELAY_AGENT_ENV" "STATE_DIR" "$STATE_DIR"
  set_env_value "$RELAY_AGENT_ENV" "STATE_FILE" "$STATE_DIR/last_event_id-$(hostname)"
  set_env_value "$RELAY_AGENT_ENV" "ACTION_FILTER" "refresh_slides"
  set_env_value "$RELAY_AGENT_ENV" "LISTEN_ONCE" "0"

  set_env_value "$RELAY_STREAM_ENV" "RELAY_URL" "$RELAY_URL"
  set_env_value "$RELAY_STREAM_ENV" "RELAY_SECRET" "$RELAY_SECRET"
  set_env_value "$RELAY_STREAM_ENV" "LOCAL_RUNNER" "$PROJECT_ROOT/scripts/slides_machine_runner.sh"
  set_env_value "$RELAY_STREAM_ENV" "LOCAL_CONFIG" "$LOCAL_ENV"
  set_env_value "$RELAY_STREAM_ENV" "RUN_LOCAL" "1"
  set_env_value "$RELAY_STREAM_ENV" "RUN_RELAY" "1"
  set_env_value "$RELAY_STREAM_ENV" "ACTION" "refresh_slides"
  set_env_value "$RELAY_STREAM_ENV" "SOURCE_LABEL" "$(hostname)"
fi

log "Configured environment files:"
log "  $LOCAL_ENV"
if [[ "$MODE" == "relay" ]]; then
  log "  $RELAY_AGENT_ENV"
  log "  $RELAY_STREAM_ENV"
fi

health_ok=1

check_env_value() {
  local file="$1" key="$2" label="$3"
  local value
  value="$(get_env_value "$file" "$key")"
  if is_placeholder "$value"; then
    log "$label invalid or missing: $key=$value"
    health_ok=0
  fi
}

check_env_value "$LOCAL_ENV" "AUTO_CAPTURE_FRONT_TAB" "local config"
check_env_value "$LOCAL_ENV" "BOUNDS_MODE" "local config"
check_env_value "$LOCAL_ENV" "DISPLAY_ASSIGNMENT" "local config"

if [[ "$MODE" == "relay" ]]; then
  check_env_value "$LOCAL_ENV" "SLIDES_SOURCE_URL" "local config"
  check_env_value "$RELAY_AGENT_ENV" "RELAY_URL" "relay agent config"
  check_env_value "$RELAY_AGENT_ENV" "RELAY_SECRET" "relay agent config"
  check_env_value "$RELAY_STREAM_ENV" "RELAY_URL" "relay trigger config"
  check_env_value "$RELAY_STREAM_ENV" "RELAY_SECRET" "relay trigger config"
fi

if [[ "$RUN_HEALTH" == "1" ]]; then
  if [[ "$MODE" == "relay" ]]; then
    log "Running relay health check"

    probe="$({
      curl -fsS --connect-timeout 8 --max-time 12 -G "$RELAY_URL" \
        --data-urlencode "secret=${RELAY_SECRET}" \
        --data-urlencode "waitSeconds=0"
    } 2>/dev/null || true)"

    if [[ -z "$probe" ]] || ! printf '%s' "$probe" | grep -q '"ok":true'; then
      log "Relay probe failed."
      health_ok=0
    else
      WORKDIR="$(mktemp -d)"
      AGENT_LOG="$WORKDIR/agent.log"
      TRIGGER_LOG="$WORKDIR/trigger.log"
      NOOP_RUNNER="$WORKDIR/noop-runner.sh"
      AGENT_CFG="$WORKDIR/agent.env"
      TRIGGER_CFG="$WORKDIR/trigger.env"

      cat > "$NOOP_RUNNER" <<'NOOP'
#!/usr/bin/env bash
set -euo pipefail
echo "noop runner executed"
NOOP
      chmod +x "$NOOP_RUNNER"

      cp "$RELAY_AGENT_ENV" "$AGENT_CFG"
      set_env_value "$AGENT_CFG" "RUNNER_PATH" "$NOOP_RUNNER"
      set_env_value "$AGENT_CFG" "STATE_FILE" "$WORKDIR/last_event_id-health"
      set_env_value "$AGENT_CFG" "LISTEN_ONCE" "1"
      set_env_value "$AGENT_CFG" "LISTEN_TIMEOUT_SECONDS" "8"
      set_env_value "$AGENT_CFG" "POLL_SECONDS" "1"
      set_env_value "$AGENT_CFG" "CURL_TIMEOUT_SECONDS" "12"
      set_env_value "$AGENT_CFG" "ACK_ON_FAILURE" "1"

      cp "$RELAY_STREAM_ENV" "$TRIGGER_CFG"
      set_env_value "$TRIGGER_CFG" "RUN_LOCAL" "0"
      set_env_value "$TRIGGER_CFG" "RUN_RELAY" "1"

      "$PROJECT_ROOT/scripts/slides_relay_agent.sh" "$AGENT_CFG" >"$AGENT_LOG" 2>&1 &
      AGENT_PID=$!

      sleep 1

      if ! "$PROJECT_ROOT/scripts/slides_relay_streamdeck_trigger.sh" "$TRIGGER_CFG" >"$TRIGGER_LOG" 2>&1; then
        log "Relay trigger failed while health testing."
        log "Trigger log:" 
        tail -n 20 "$TRIGGER_LOG" || true
        health_ok=0
      else
        for _ in {1..20}; do
          if grep -qE "Event .* processed|Runner failed for event" "$AGENT_LOG"; then
            break
          fi
          if ! kill -0 "$AGENT_PID" >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        if grep -qE "Event .* processed|Runner failed for event" "$AGENT_LOG"; then
          log "Relay round-trip check passed."
        else
          log "Relay round-trip check failed (timeout)."
          log "Agent log (tail):"
          tail -n 60 "$AGENT_LOG" || true
          health_ok=0
        fi
      fi
    fi
  else
    log "Local mode: skipping relay health checks."
  fi
fi

if [[ "$RUN_HEALTH" == "1" && "$health_ok" -ne 1 ]]; then
  log "Health checks failed. Please re-run after resolving relay/connectivity config." >&2
  exit 1
fi

log "Setup complete."
log "Next steps:"
log "  - Open a Google Slides deck in Chrome on this machine."
log "  - Run local automation once: $PROJECT_ROOT/scripts/slides_machine_runner.sh $LOCAL_ENV"
if [[ "$MODE" == "relay" ]]; then
  log "  - Trigger from this machine: $PROJECT_ROOT/scripts/slides_relay_streamdeck_trigger.sh $RELAY_STREAM_ENV"
  log "  - On other laptops, configure relay-agent with same RELAY_URL/RELAY_SECRET and run: $PROJECT_ROOT/scripts/slides_relay_agent.sh path/to/relay_agent.env"
fi
