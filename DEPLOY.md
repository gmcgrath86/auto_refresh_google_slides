# Deploy Guide (Presentation Machines)

This guide gets this project running on one or two managed macOS presentation laptops quickly and repeatably.

## 1) Clone the repo
```bash
git clone https://github.com/gmcgrath86/auto_refresh_google_slides.git "$HOME/auto_refresh_google_slides"
cd "$HOME/auto_refresh_google_slides"
```

If already cloned:
```bash
git -C "$HOME/auto_refresh_google_slides" pull
```

Single-command bootstrap (clone-or-update + hotkey + local config defaults):
```bash
set -euo pipefail
REPO_DIR="$HOME/auto_refresh_google_slides"
REPO_URL="https://github.com/gmcgrath86/auto_refresh_google_slides.git"

if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

"$REPO_DIR/scripts/bootstrap_machine.sh" --role presentation --install-hotkey --hotkey-mode local

FILE="$REPO_DIR/config/local.env"
grep -q '^SLIDES_SOURCE_URL=' "$FILE" && sed -i '' 's|^SLIDES_SOURCE_URL=.*|SLIDES_SOURCE_URL=""|' "$FILE" || echo 'SLIDES_SOURCE_URL=""' >> "$FILE"
grep -q '^AUTO_CAPTURE_FRONT_TAB=' "$FILE" && sed -i '' 's|^AUTO_CAPTURE_FRONT_TAB=.*|AUTO_CAPTURE_FRONT_TAB=1|' "$FILE" || echo 'AUTO_CAPTURE_FRONT_TAB=1' >> "$FILE"
grep -q '^PRIMARY_BOUNDS=' "$FILE" && sed -i '' 's|^PRIMARY_BOUNDS=.*|PRIMARY_BOUNDS="1920,25,3840,1080"|' "$FILE" || echo 'PRIMARY_BOUNDS="1920,25,3840,1080"' >> "$FILE"
grep -q '^NOTES_BOUNDS=' "$FILE" && sed -i '' 's|^NOTES_BOUNDS=.*|NOTES_BOUNDS="0,25,1920,1080"|' "$FILE" || echo 'NOTES_BOUNDS="0,25,1920,1080"' >> "$FILE"

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
- `PRIMARY_BOUNDS`
- `NOTES_BOUNDS`

Optional (already tuned fast/stable defaults):
- `LAUNCH_DELAY_SECONDS`
- `PRESENTER_READY_DELAY_SECONDS`
- `NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS`
- `NOTES_ZOOM_STEPS` (default `7` for larger presenter notes text)
- `NOTES_ZOOM_STEP_DELAY_SECONDS`

Non-interactive way to set required values:
```bash
FILE="$HOME/auto_refresh_google_slides/config/local.env"
grep -q '^SLIDES_SOURCE_URL=' "$FILE" && sed -i '' 's|^SLIDES_SOURCE_URL=.*|SLIDES_SOURCE_URL=""|' "$FILE" || echo 'SLIDES_SOURCE_URL=""' >> "$FILE"
grep -q '^AUTO_CAPTURE_FRONT_TAB=' "$FILE" && sed -i '' 's|^AUTO_CAPTURE_FRONT_TAB=.*|AUTO_CAPTURE_FRONT_TAB=1|' "$FILE" || echo 'AUTO_CAPTURE_FRONT_TAB=1' >> "$FILE"
grep -q '^PRIMARY_BOUNDS=' "$FILE" && sed -i '' 's|^PRIMARY_BOUNDS=.*|PRIMARY_BOUNDS="1920,25,3840,1080"|' "$FILE" || echo 'PRIMARY_BOUNDS="1920,25,3840,1080"' >> "$FILE"
grep -q '^NOTES_BOUNDS=' "$FILE" && sed -i '' 's|^NOTES_BOUNDS=.*|NOTES_BOUNDS="0,25,1920,1080"|' "$FILE" || echo 'NOTES_BOUNDS="0,25,1920,1080"' >> "$FILE"
```

## 4) macOS permissions
Enable Accessibility for the app/process running automation:
- `System Settings -> Privacy & Security -> Accessibility`

If using Hammerspoon hotkey, enable:
- `Hammerspoon`

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
