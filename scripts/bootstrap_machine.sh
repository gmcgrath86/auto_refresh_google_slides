#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bootstrap_machine.sh [--role presentation|relay-agent|controller|all] [--install-hotkey] [--install-launch-agent]

Roles:
  presentation  Create config/local.env if missing and prep local runner.
  relay-agent   Create config/relay_agent.env if missing.
  controller    Create controller trigger configs if missing.
  all           Prepare all local config files (default).

Hotkey options:
  --install-hotkey          Install/configure Hammerspoon hotkey integration.
  --hotkey-mode MODE        local|relay|ssh (default: local)
  --hotkey-config PATH      Config file path for selected mode (default based on mode)
  --hotkey-mods CSV         Hotkey modifiers (default: ctrl,alt,cmd)
  --hotkey-key KEY          Hotkey key (default: r)
  --http-interface IFACE    Hammerspoon HTTP bind interface (default: en0)
  --install-launch-agent    Auto-start/restart Hammerspoon after GUI login.
USAGE
}

ROLE="all"
INSTALL_HOTKEY=0
INSTALL_LAUNCH_AGENT=0
HOTKEY_MODE="local"
HOTKEY_CONFIG=""
HOTKEY_MODS_CSV="ctrl,alt,cmd"
HOTKEY_KEY="r"
HTTP_INTERFACE="en0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    --install-hotkey)
      INSTALL_HOTKEY=1
      shift 1
      ;;
    --install-launch-agent)
      INSTALL_LAUNCH_AGENT=1
      shift 1
      ;;
    --hotkey-mode)
      HOTKEY_MODE="${2:-}"
      shift 2
      ;;
    --hotkey-config)
      HOTKEY_CONFIG="${2:-}"
      shift 2
      ;;
    --hotkey-mods)
      HOTKEY_MODS_CSV="${2:-}"
      shift 2
      ;;
    --hotkey-key)
      HOTKEY_KEY="${2:-}"
      shift 2
      ;;
    --http-interface)
      HTTP_INTERFACE="${2:-}"
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
HOME_HAMMERSPOON_DIR="$HOME/.hammerspoon"

lua_escape() {
  local input="$1"
  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  printf '%s' "$input"
}

ensure_hammerspoon_installed() {
  if [[ -d /Applications/Hammerspoon.app ]]; then
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "Hammerspoon is not installed and Homebrew was not found." >&2
    echo "Install one of the following, then rerun the bootstrap command:" >&2
    echo "  1) Homebrew path (recommended): brew install --cask hammerspoon" >&2
    echo "  2) Manual path: download latest .dmg from https://github.com/Hammerspoon/hammerspoon/releases/latest" >&2
    echo "     and drag Hammerspoon.app into /Applications" >&2
    exit 1
  fi

  echo "Installing Hammerspoon..."
  brew install --cask hammerspoon
}

setup_hammerspoon_hotkey() {
  local hotkey_config_path
  local project_root_lua
  local trigger_config_lua
  local init_file
  local hook_line
  local lua_mods
  local old_ifs
  local one_mod

  case "$HOTKEY_MODE" in
    local)
      hotkey_config_path="$PROJECT_ROOT/config/local.env"
      ;;
    relay)
      hotkey_config_path="$PROJECT_ROOT/config/relay_streamdeck.env"
      ;;
    ssh)
      hotkey_config_path="$PROJECT_ROOT/config/controller.env"
      ;;
    *)
      echo "Invalid --hotkey-mode: $HOTKEY_MODE (expected: local, relay, ssh)" >&2
      exit 1
      ;;
  esac

  if [[ -n "$HOTKEY_CONFIG" ]]; then
    hotkey_config_path="$HOTKEY_CONFIG"
  fi

  ensure_hammerspoon_installed

  mkdir -p "$HOME_HAMMERSPOON_DIR"

  project_root_lua="$(lua_escape "$PROJECT_ROOT")"
  trigger_config_lua="$(lua_escape "$hotkey_config_path")"

  lua_mods=""
  old_ifs="$IFS"
  IFS=','
  for one_mod in $HOTKEY_MODS_CSV; do
    one_mod="${one_mod#"${one_mod%%[![:space:]]*}"}"
    one_mod="${one_mod%"${one_mod##*[![:space:]]}"}"
    if [[ -n "$one_mod" ]]; then
      if [[ -n "$lua_mods" ]]; then
        lua_mods+=", "
      fi
      lua_mods+="\"$one_mod\""
    fi
  done
  IFS="$old_ifs"

  if [[ -z "$lua_mods" ]]; then
    lua_mods="\"ctrl\", \"alt\", \"cmd\""
  fi

  local template_lua="$PROJECT_ROOT/config/hammerspoon.init.lua.example"
  local hotkey_lua="$HOME_HAMMERSPOON_DIR/slides_hotkey.lua"

  if [[ ! -f "$template_lua" ]]; then
    echo "Missing template: $template_lua" >&2
    exit 1
  fi

  cp "$template_lua" "$hotkey_lua"

  sed -i '' "s|^local projectRoot = .*|local projectRoot = \"$project_root_lua\"|" "$hotkey_lua"
  sed -i '' "s|^local triggerMode = .*|local triggerMode = \"$HOTKEY_MODE\"|" "$hotkey_lua"
  sed -i '' "s|^local triggerConfig = .*|local triggerConfig = \"$trigger_config_lua\"|" "$hotkey_lua"
  sed -i '' "s|^local hotkeyMods = .*|local hotkeyMods = {$lua_mods}|" "$hotkey_lua"
  sed -i '' "s|^local hotkeyKey = .*|local hotkeyKey = \"$HOTKEY_KEY\"|" "$hotkey_lua"
  sed -i '' "s|^local httpInterface = .*|local httpInterface = \"$HTTP_INTERFACE\"|" "$hotkey_lua"

  init_file="$HOME_HAMMERSPOON_DIR/init.lua"
  local ipc_line
  hook_line='dofile(os.getenv("HOME") .. "/.hammerspoon/slides_hotkey.lua")'
  ipc_line='require("hs.ipc")'

  if [[ -f "$init_file" ]]; then
    if ! grep -Fq "$ipc_line" "$init_file"; then
      {
        echo ""
        echo "-- Allow `hs -c` reloads from shell"
        echo "$ipc_line"
      } >> "$init_file"
    fi
    if ! grep -Fq "$hook_line" "$init_file"; then
      {
        echo ""
        echo "-- Slides hotkey integration"
        echo "$hook_line"
      } >> "$init_file"
    fi
  else
    cat > "$init_file" <<EOF
-- Hammerspoon init created by bootstrap_machine.sh
$ipc_line
$hook_line
EOF
  fi

  open -a Hammerspoon
  sleep 1
  if command -v hs >/dev/null 2>&1; then
    hs -c 'hs.reload()' >/dev/null 2>&1 || true
  fi

  echo "Hotkey setup complete."
  echo "Configured: $HOME_HAMMERSPOON_DIR/slides_hotkey.lua"
  echo "Hotkey: $HOTKEY_MODS_CSV+$HOTKEY_KEY"
  echo "Mode/config: $HOTKEY_MODE -> $hotkey_config_path"
  echo "HTTP interface: $HTTP_INTERFACE"
  echo "If hotkey still does nothing, enable Accessibility for Hammerspoon:"
  echo "System Settings -> Privacy & Security -> Accessibility -> Hammerspoon"
  echo "Remote trigger endpoint: http://<this-machine-ip>:8765/slides/run"
  echo "Remote load endpoint:    http://<this-machine-ip>:8765/slides/load?presentation_id=<id>"
  echo "Remote Keynote endpoint: http://<this-machine-ip>:8765/keynote/load?icloud_relative_path=<path.key>"
  echo "Remote status endpoint:  http://<this-machine-ip>:8765/slides/status"
  echo "Remote health endpoint:  http://<this-machine-ip>:8765/slides/health"
  echo "Remote jump endpoint:    http://<this-machine-ip>:8765/slides/jump/<number>"
  echo "Remote notes endpoint:   http://<this-machine-ip>:8765/slides/notes/font/up/<steps>"
  echo "Remote layout endpoint:  http://<this-machine-ip>:8765/slides/notes/layout/80"
}

setup_hammerspoon_launch_agent() {
  local template_plist="$PROJECT_ROOT/launchd/com.codex.slides-hammerspoon.plist.example"
  local launch_agents_dir="$HOME/Library/LaunchAgents"
  local launch_agent_plist="$launch_agents_dir/com.codex.slides-hammerspoon.plist"
  local user_domain="gui/$(id -u)"

  ensure_hammerspoon_installed

  if [[ ! -f "$template_plist" ]]; then
    echo "Missing template: $template_plist" >&2
    exit 1
  fi

  mkdir -p "$launch_agents_dir"
  cp "$template_plist" "$launch_agent_plist"
  plutil -lint "$launch_agent_plist" >/dev/null

  launchctl bootout "$user_domain" "$launch_agent_plist" >/dev/null 2>&1 || true
  launchctl bootstrap "$user_domain" "$launch_agent_plist"
  launchctl enable "$user_domain/com.codex.slides-hammerspoon"

  # Avoid keeping an old manually-opened Hammerspoon instance alongside launchd.
  /usr/bin/osascript -e 'quit application "Hammerspoon"' >/dev/null 2>&1 || true
  sleep 1
  launchctl kickstart -k "$user_domain/com.codex.slides-hammerspoon"

  echo "Hammerspoon LaunchAgent setup complete."
  echo "LaunchAgent: $launch_agent_plist"
  echo "Logs: /tmp/slides-hammerspoon-launchd.out.log"
  echo "Logs: /tmp/slides-hammerspoon-launchd.err.log"
}

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

if [[ "$INSTALL_HOTKEY" == "1" ]]; then
  setup_hammerspoon_hotkey
fi

if [[ "$INSTALL_LAUNCH_AGENT" == "1" ]]; then
  setup_hammerspoon_launch_agent
fi

echo "Done. Next: edit config files for this machine, then run the matching script from README/DEPLOY.md."
