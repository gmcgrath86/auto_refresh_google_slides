# Deploy Guide (Presentation Machines)

This guide gets this project running on one or two managed macOS presentation laptops quickly and repeatably.

## 1) Clone the repo
```bash
git clone https://github.com/gmcgrath86/auto_refresh_google_slides.git "$HOME/auto_refresh_google_slides"
cd "$HOME/auto_refresh_google_slides"
```

If already cloned:
```bash
git -C "$HOME/auto_refresh_google_slides" pull --ff-only --tags
```

Single-command bootstrap (clone-or-update + hotkey + local config defaults):
```bash
set -euo pipefail
REPO_DIR="$HOME/auto_refresh_google_slides"
REPO_URL="https://github.com/gmcgrath86/auto_refresh_google_slides.git"

if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only --tags
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

"$REPO_DIR/scripts/bootstrap_machine.sh" --role presentation --install-hotkey --hotkey-mode local

FILE="$REPO_DIR/config/local.env"
grep -q '^SLIDES_SOURCE_URL=' "$FILE" && sed -i '' 's|^SLIDES_SOURCE_URL=.*|SLIDES_SOURCE_URL=""|' "$FILE" || echo 'SLIDES_SOURCE_URL=""' >> "$FILE"
grep -q '^AUTO_CAPTURE_FRONT_TAB=' "$FILE" && sed -i '' 's|^AUTO_CAPTURE_FRONT_TAB=.*|AUTO_CAPTURE_FRONT_TAB=1|' "$FILE" || echo 'AUTO_CAPTURE_FRONT_TAB=1' >> "$FILE"
grep -q '^BOUNDS_MODE=' "$FILE" && sed -i '' 's|^BOUNDS_MODE=.*|BOUNDS_MODE="auto"|' "$FILE" || echo 'BOUNDS_MODE="auto"' >> "$FILE"
grep -q '^DISPLAY_ASSIGNMENT=' "$FILE" && sed -i '' 's|^DISPLAY_ASSIGNMENT=.*|DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"|' "$FILE" || echo 'DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"' >> "$FILE"
grep -q '^NOTES_PLUS_METHOD=' "$FILE" && sed -i '' 's|^NOTES_PLUS_METHOD=.*|NOTES_PLUS_METHOD="auto"|' "$FILE" || echo 'NOTES_PLUS_METHOD="auto"' >> "$FILE"

echo "Done. Open a Google Slides tab in Chrome and press ctrl+alt+cmd+r."
```

## 2) Bootstrap machine files
```bash
./scripts/bootstrap_machine.sh --role presentation
```

That creates machine-local config files if missing and makes scripts executable.

To also install and wire the global hotkey in one shot:
```bash
"$HOME/auto_refresh_google_slides/scripts/bootstrap_machine.sh" --role presentation --install-hotkey --hotkey-mode local
```

## 3) Configure this machine
Edit:
- `config/local.env`

Set at minimum:
- `AUTO_CAPTURE_FRONT_TAB=1`
- `BOUNDS_MODE="auto"`
- `DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"`

Optional (already tuned fast/stable defaults):
- `LAUNCH_DELAY_SECONDS`
- `PRESENTER_READY_DELAY_SECONDS`
- `NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS`
- `NOTES_SHORTCUT_MAX_WAIT_SECONDS` (increase for very large decks or slower load)
- `NOTES_PLUS_CLICK_STEPS` (default `7`, clicks notes `+` control)
- `NOTES_PLUS_METHOD` (`auto`, `js`, or `coords`)
- `NOTES_PLUS_READY_DELAY_SECONDS` (delay after notes fullscreen before clicking)
- `NOTES_PLUS_CLICK_DELAY_SECONDS`
- `NOTES_PLUS_BUTTON_RIGHT_OFFSET`
- `NOTES_PLUS_BUTTON_TOP_OFFSET`
- `PRIMARY_BOUNDS` / `NOTES_BOUNDS` only when `BOUNDS_MODE="manual"`

Non-interactive way to set required values:
```bash
FILE="$HOME/auto_refresh_google_slides/config/local.env"
grep -q '^SLIDES_SOURCE_URL=' "$FILE" && sed -i '' 's|^SLIDES_SOURCE_URL=.*|SLIDES_SOURCE_URL=""|' "$FILE" || echo 'SLIDES_SOURCE_URL=""' >> "$FILE"
grep -q '^AUTO_CAPTURE_FRONT_TAB=' "$FILE" && sed -i '' 's|^AUTO_CAPTURE_FRONT_TAB=.*|AUTO_CAPTURE_FRONT_TAB=1|' "$FILE" || echo 'AUTO_CAPTURE_FRONT_TAB=1' >> "$FILE"
grep -q '^BOUNDS_MODE=' "$FILE" && sed -i '' 's|^BOUNDS_MODE=.*|BOUNDS_MODE="auto"|' "$FILE" || echo 'BOUNDS_MODE="auto"' >> "$FILE"
grep -q '^DISPLAY_ASSIGNMENT=' "$FILE" && sed -i '' 's|^DISPLAY_ASSIGNMENT=.*|DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"|' "$FILE" || echo 'DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"' >> "$FILE"
grep -q '^NOTES_PLUS_METHOD=' "$FILE" && sed -i '' 's|^NOTES_PLUS_METHOD=.*|NOTES_PLUS_METHOD="auto"|' "$FILE" || echo 'NOTES_PLUS_METHOD="auto"' >> "$FILE"
```

Optional one-time notes `+` calibration:
```bash
"$HOME/auto_refresh_google_slides/scripts/calibrate_notes_plus.sh" "$HOME/auto_refresh_google_slides/config/local.env"
```

## 4) macOS permissions
Enable Accessibility for the app/process running automation:
- `System Settings -> Privacy & Security -> Accessibility`

If using Hammerspoon hotkey, enable:
- `Hammerspoon`

Recommended for JS-first notes-clicking:
- Chrome -> `View -> Developer -> Allow JavaScript from Apple Events`

## 5) Validate local runner
```bash
"$HOME/auto_refresh_google_slides/scripts/slides_machine_runner.sh" "$HOME/auto_refresh_google_slides/config/local.env"
```

Expected result:
- Slides fullscreen on extended display.
- Presenter notes fullscreen on mirrored/local display.

## 6) Hotkey setup (optional)
Recommended:
```bash
"$HOME/auto_refresh_google_slides/scripts/bootstrap_machine.sh" --role presentation --install-hotkey --hotkey-mode local
```

Manual alternative:
- Install Hammerspoon (`brew install --cask hammerspoon`)
- Create `~/.hammerspoon/slides_hotkey.lua`
- Ensure `~/.hammerspoon/init.lua` includes:
```lua
dofile(os.getenv("HOME") .. "/.hammerspoon/slides_hotkey.lua")
```

Default hotkey:
- `ctrl+alt+cmd+r`

Verification:
```bash
tail -n 60 /tmp/slides-hotkey.log
```

## 7) Two-machine trigger options

### Option A: Outbound-only relay (recommended on managed networks)
On each laptop, bootstrap relay agent files:
```bash
./scripts/bootstrap_machine.sh --role relay-agent
```

Edit on each laptop:
- `config/relay_agent.env`
- Optional near-realtime tuning:
  - `LISTEN_TIMEOUT_SECONDS` (long-poll window, default 20)
  - `POLL_SECONDS` (fallback poll sleep, default 2)

On Stream Deck/controller machine:
```bash
./scripts/bootstrap_machine.sh --role controller
```

Edit:
- `config/relay_streamdeck.env`

Trigger test:
```bash
./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```

One-shot remote listener test:
- Set `LISTEN_ONCE=1` in the remote laptop's `config/relay_agent.env`.
- Run:
```bash
./scripts/slides_relay_agent.sh ./config/relay_agent.env
```
- From this machine, send one event:
```bash
./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```

### Option B: Direct SSH (only if inbound SSH allowed)
```bash
./scripts/bootstrap_machine.sh --role controller
```
Edit `config/controller.env`, then run:
```bash
./scripts/slides_streamdeck_trigger.sh ./config/controller.env
```

## 8) Stream Deck binding
Use `System -> Open` or `System -> Command`:
```bash
cd '/ABSOLUTE/PATH/auto_refresh_google_slides' && ./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```

For single-machine only:
```bash
cd '/ABSOLUTE/PATH/auto_refresh_google_slides' && ./scripts/slides_hotkey_trigger.sh --mode local --config ./config/local.env
```

## Update workflow
On deployed machines, pull tags with updates:
```bash
git -C "$HOME/auto_refresh_google_slides" pull --ff-only --tags
```
