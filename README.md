# Google Slides Dual-Machine Stream Deck Automation (macOS)

This project supports two control modes:
- SSH mode: one machine directly triggers the second over SSH.
- Outbound-only relay mode: both machines subscribe to a cloud webhook relay, so no inbound sharing is required.
  - Trigger path: local controller posts command -> relay stores event -> each laptop listens for new event -> runner executes.

For managed laptops where Sharing/SSH is blocked, use relay mode.

Quick deployment:
- See `DEPLOY.md` for machine-by-machine rollout steps.
- Bootstrap any machine with `./scripts/bootstrap_machine.sh --role <presentation|relay-agent|controller>`.
- Fresh machine with hotkey in one command:
  - `./scripts/bootstrap_machine.sh --role presentation --install-hotkey`
- Remote operator one-shot setup (recommended on managed laptops):
  - `./scripts/one_shot_remote_setup.sh`

Example relay command for a brand-new machine:

```bash
REPO_DIR="$HOME/auto_refresh_google_slides"
RELAY_URL="https://script.google.com/macros/s/<YOUR_DEPLOYMENT_ID>/exec"
RELAY_SECRET="<YOUR_SHARED_SECRET>"
SLIDES_SOURCE_URL="https://docs.google.com/presentation/d/<DECK_ID>/edit"

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone https://github.com/gmcgrath86/auto_refresh_google_slides.git "$REPO_DIR"
fi

"$REPO_DIR/scripts/one_shot_remote_setup.sh" \
  --repo-dir "$REPO_DIR" \
  --mode relay \
  --slides-url "$SLIDES_SOURCE_URL" \
  --relay-url "$RELAY_URL" \
  --relay-secret "$RELAY_SECRET"
```

## Fresh Machine Quickstart (Single Laptop + Hotkey)
Run these exact commands on a new presentation machine:

```bash
git clone https://github.com/gmcgrath86/auto_refresh_google_slides.git "$HOME/auto_refresh_google_slides"
"$HOME/auto_refresh_google_slides/scripts/bootstrap_machine.sh" --role presentation --install-hotkey --hotkey-mode local
```

One-paste robust command (works whether repo is already present or not):

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

tail -n 20 /tmp/slides-hotkey.log 2>/dev/null || true
echo "Ready. Open a Google Slides tab in Chrome, then press ctrl+alt+cmd+r."
```

Then set the required local values:

```bash
FILE="$HOME/auto_refresh_google_slides/config/local.env"
grep -q '^SLIDES_SOURCE_URL=' "$FILE" && sed -i '' 's|^SLIDES_SOURCE_URL=.*|SLIDES_SOURCE_URL=""|' "$FILE" || echo 'SLIDES_SOURCE_URL=""' >> "$FILE"
grep -q '^AUTO_CAPTURE_FRONT_TAB=' "$FILE" && sed -i '' 's|^AUTO_CAPTURE_FRONT_TAB=.*|AUTO_CAPTURE_FRONT_TAB=1|' "$FILE" || echo 'AUTO_CAPTURE_FRONT_TAB=1' >> "$FILE"
grep -q '^BOUNDS_MODE=' "$FILE" && sed -i '' 's|^BOUNDS_MODE=.*|BOUNDS_MODE="auto"|' "$FILE" || echo 'BOUNDS_MODE="auto"' >> "$FILE"
grep -q '^DISPLAY_ASSIGNMENT=' "$FILE" && sed -i '' 's|^DISPLAY_ASSIGNMENT=.*|DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"|' "$FILE" || echo 'DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"' >> "$FILE"
grep -q '^NOTES_PLUS_METHOD=' "$FILE" && sed -i '' 's|^NOTES_PLUS_METHOD=.*|NOTES_PLUS_METHOD="auto"|' "$FILE" || echo 'NOTES_PLUS_METHOD="auto"' >> "$FILE"
```

Final checks:
- Turn on `Hammerspoon` in `System Settings -> Privacy & Security -> Accessibility`.
- Open a Slides deck in Chrome.
- Press `ctrl+alt+cmd+r`.
- Verify with `tail -n 60 /tmp/slides-hotkey.log`.

## What this solves
One Stream Deck button can:
1. Relaunch Slides presentation + notes windows locally.
2. Put notes on the secondary monitor and fullscreen it.
3. Signal the second laptop to do the same (without inbound network access).

## Files
- `scripts/slides_machine_runner.sh`: Opens/positions/fullscreens Slides windows on one machine.
- `scripts/slides_hotkey_trigger.sh`: Hotkey-safe wrapper with lock/logging that can call local/relay/ssh triggers.
- `scripts/bootstrap_machine.sh`: Creates machine-local config files and normalizes script permissions.
- `scripts/one_shot_remote_setup.sh`: One-shot bootstrap + config wiring + optional relay health checks for remote operators.
- `scripts/get_chrome_front_window_bounds.sh`: Prints front Chrome window bounds for calibration.
- `scripts/calibrate_notes_plus.sh`: Captures exact notes `+` offsets from live mouse position.
- `scripts/slides_streamdeck_trigger.sh`: SSH orchestrator (local + remote SSH).
- `scripts/slides_relay_streamdeck_trigger.sh`: Relay orchestrator (local + cloud event post).
- `scripts/slides_relay_agent.sh`: Polling agent each laptop runs to react to relay events.
- `config/local.env.example`: Local machine Slides config template.
- `config/remote.env.example`: Remote machine Slides config template (SSH mode).
- `config/controller.env.example`: SSH controller config template.
- `config/relay_streamdeck.env.example`: Relay trigger config template.
- `config/relay_agent.env.example`: Relay agent config template.
- `config/hammerspoon.init.lua.example`: Global-hotkey example config for Hammerspoon.
- `relay/google_apps_script_webhook.gs`: Google Apps Script webhook relay source.
- `launchd/com.codex.slides-relay-agent.plist.example`: LaunchAgent template for auto-starting relay agent.
- `DEPLOY.md`: Practical deployment playbook for presentation laptops and controller machine.

## Prerequisites
- macOS on both machines.
- Google Chrome installed and signed into the deck account.
- Accessibility permission for the app running scripts:
  - System Settings -> Privacy & Security -> Accessibility.
- If using SSH mode only: Remote Login enabled and reachable.

## Common setup (both modes)
1. Copy local template:
```bash
cp config/local.env.example config/local.env
```

2. Edit `config/local.env`:
- `SLIDES_SOURCE_URL` (recommended; your normal `/edit` deck URL)
- optionally `SLIDES_PRESENT_URL` if you want to bypass auto-derivation
- optionally `SLIDES_NOTES_URL` if you don't want shortcut-generated notes
- `BOUNDS_MODE` (`auto` recommended, `manual` available)
- `DISPLAY_ASSIGNMENT` (`slides:rightmost,notes:leftmost`)
- optional manual-only: `PRIMARY_BOUNDS`, `NOTES_BOUNDS`
- optional timing tune:
  - `LAUNCH_DELAY_SECONDS` (post-action settle delay)
  - `PRESENTER_READY_DELAY_SECONDS` (initial readiness target before note retries)
  - `NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS` (retry interval for notes shortcut)
  - `NOTES_SHORTCUT_MAX_WAIT_SECONDS` (hard cap for notes shortcut retries; increase for very large decks)
  - `NOTES_PLUS_CLICK_STEPS` (number of clicks on the notes `+` control after fullscreen)
  - `NOTES_PLUS_METHOD` (`auto`, `js`, or `coords`)
  - `NOTES_PLUS_READY_DELAY_SECONDS` (delay after notes fullscreen before clicking `+`)
  - `NOTES_PLUS_CLICK_DELAY_SECONDS` (delay between notes `+` clicks)
  - `NOTES_PLUS_BUTTON_RIGHT_OFFSET` (pixels from notes window right edge to `+` click point)
  - `NOTES_PLUS_BUTTON_TOP_OFFSET` (pixels from notes window top edge to `+` click point)

3. Make scripts executable:
```bash
chmod +x scripts/*.sh
```

4. (Optional) calibrate notes `+` offsets:
```bash
./scripts/calibrate_notes_plus.sh ./config/local.env
```

5. Local runner test:
```bash
./scripts/slides_machine_runner.sh ./config/local.env
```

6. For best JS notes-click reliability, enable in Chrome:
- `View -> Developer -> Allow JavaScript from Apple Events`

## Relay mode (recommended for blocked sharing)

### 1) Deploy relay webhook in Google Apps Script
1. Open [script.google.com](https://script.google.com) and create a new Apps Script project.
2. Replace the default script with `relay/google_apps_script_webhook.gs`.
3. Save, then run `setupRelay('YOUR_LONG_RANDOM_SECRET')` once from the editor.
4. Deploy -> New deployment -> Web app.
5. Set:
- Execute as: `Me`
- Who has access: `Anyone`
6. Copy the deployed `.../exec` URL.

### 2) Configure trigger machine (Stream Deck machine)
1. Copy template:
```bash
cp config/relay_streamdeck.env.example config/relay_streamdeck.env
```

2. Edit `config/relay_streamdeck.env`:
- `RELAY_URL` = your Apps Script `/exec` URL
- `RELAY_SECRET` = same secret used in `setupRelay(...)`
- Keep `RUN_LOCAL=1` so this machine refreshes instantly.

### 3) Configure each laptop polling agent
On each laptop:
1. Copy template:
```bash
cp config/relay_agent.env.example config/relay_agent.env
```

2. Edit `config/relay_agent.env`:
- `RELAY_URL`
- `RELAY_SECRET`
- `RUNNER_CONFIG` (usually that machine's `config/local.env`)
- Give each machine a unique `STATE_FILE`.
- Optional low-latency tuning:
  - `LISTEN_TIMEOUT_SECONDS` (long-poll wait window, default 20)
  - `POLL_SECONDS` (fallback sleep, default 2)

3. Test agent in foreground:
```bash
./scripts/slides_relay_agent.sh ./config/relay_agent.env
```

### 4) Test relay trigger
From controller machine:
```bash
./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```

For a one-shot remote check from this machine:
- On remote laptop, temporarily set `LISTEN_ONCE=1` in `config/relay_agent.env`.
- Run the agent in foreground:
```bash
./scripts/slides_relay_agent.sh ./config/relay_agent.env
```
- Trigger once from this machine:
```bash
./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```
- The listener should log the event and run the local runner, then exit.

### 5) Bind Stream Deck key
Use `System -> Open` or `System -> Command` with:
```bash
cd '/ABSOLUTE/PATH/auto_refresh_google_slides' && ./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```

### 6) Optional: run relay agent as LaunchAgent
On each laptop:
```bash
cp launchd/com.codex.slides-relay-agent.plist.example ~/Library/LaunchAgents/com.codex.slides-relay-agent.plist
```

Edit `~/Library/LaunchAgents/com.codex.slides-relay-agent.plist` and replace `/ABSOLUTE/PATH/TO/PROJECT`.

Then load it:
```bash
launchctl unload ~/Library/LaunchAgents/com.codex.slides-relay-agent.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.codex.slides-relay-agent.plist
```

Logs:
- `/tmp/slides-relay-agent.log`
- `/tmp/slides-relay-agent.err.log`

## SSH mode (if your network allows it)
1. Copy templates:
```bash
cp config/remote.env.example config/remote.env
cp config/controller.env.example config/controller.env
```

2. Edit `config/controller.env` with `REMOTE_SSH_TARGET` and paths.

3. Run:
```bash
./scripts/slides_streamdeck_trigger.sh ./config/controller.env
```

## Troubleshooting
- Fullscreen toggle fails: Accessibility permission missing.
- Wrong monitor placement: recalibrate bounds.
- Notes resize used coordinate fallback: enable `View -> Developer -> Allow JavaScript from Apple Events` in Chrome.
- Relay agent not triggering: verify `RELAY_URL`, `RELAY_SECRET`, and that `doGet` returns JSON with `ok:true`.
- Repeated triggering on startup: keep `FIRE_ON_STARTUP=0`.
- `Access Denied` in Chrome: the deck URL/account pair is not accessible in that Chrome profile. Open a deck that works in that profile and set `SLIDES_SOURCE_URL` to that URL.
- `Unable to determine launch URL`: no open Google Slides tab was found. Keep at least one `docs.google.com/presentation/d/...` tab open in Chrome.

## Global hotkey (while presenting)
If you want a keyboard hotkey that works even when Chrome is fullscreen:

1. Easiest setup (recommended):
```bash
./scripts/bootstrap_machine.sh --role presentation --install-hotkey
```

2. Use the wrapper script:
```bash
./scripts/slides_hotkey_trigger.sh --mode local --config ./config/local.env
```

3. Install Hammerspoon:
```bash
brew install --cask hammerspoon
```

4. Copy the example config:
```bash
cp config/hammerspoon.init.lua.example ~/.hammerspoon/init.lua
```

5. Edit `~/.hammerspoon/init.lua`:
- Set `projectRoot` to your project path.
- Choose `triggerMode`:
  - `"local"` for this laptop only
  - `"relay"` for outbound-only dual-laptop trigger
  - `"ssh"` for direct SSH dual-laptop trigger
- Set `triggerConfig` to the matching config file.
- Pick your key combo (`hotkeyMods` + `hotkeyKey`).

6. Open Hammerspoon, grant Accessibility permission, and click `Reload Config`.

7. Press your hotkey (default in example: `ctrl+alt+cmd+r`).

Notes:
- Stream Deck can send the same hotkey if you prefer pressing a Stream Deck key.
- Logs are written to `/tmp/slides-hotkey.log`.

## Deck behavior
With `SLIDES_SOURCE_URL=""` and `AUTO_CAPTURE_FRONT_TAB=1`, this works for any Google Slides deck:
- Open the deck you want in Chrome.
- Make it the active tab (recommended).
- Press the hotkey or trigger script.
