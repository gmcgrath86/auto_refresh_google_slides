# Google Slides Dual-Machine Stream Deck Automation (macOS)

This project supports two control modes:
- SSH mode: one machine directly triggers the second over SSH.
- Outbound-only relay mode: both machines poll a cloud webhook relay, so no inbound sharing is required.

For managed laptops where Sharing/SSH is blocked, use relay mode.

Quick deployment:
- See `DEPLOY.md` for machine-by-machine rollout steps.
- Bootstrap any machine with `./scripts/bootstrap_machine.sh --role <presentation|relay-agent|controller>`.

## What this solves
One Stream Deck button can:
1. Relaunch Slides presentation + notes windows locally.
2. Put notes on the secondary monitor and fullscreen it.
3. Signal the second laptop to do the same (without inbound network access).

## Files
- `scripts/slides_machine_runner.sh`: Opens/positions/fullscreens Slides windows on one machine.
- `scripts/slides_hotkey_trigger.sh`: Hotkey-safe wrapper with lock/logging that can call local/relay/ssh triggers.
- `scripts/bootstrap_machine.sh`: Creates machine-local config files and normalizes script permissions.
- `scripts/get_chrome_front_window_bounds.sh`: Prints front Chrome window bounds for calibration.
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
- `PRIMARY_BOUNDS`
- `NOTES_BOUNDS`
- optional timing tune:
  - `LAUNCH_DELAY_SECONDS` (post-action settle delay)
  - `PRESENTER_READY_DELAY_SECONDS` (max time to keep retrying notes shortcut)
  - `NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS` (retry interval for notes shortcut)

3. Make scripts executable:
```bash
chmod +x scripts/*.sh
```

4. Calibrate bounds (run on each machine):
```bash
./scripts/get_chrome_front_window_bounds.sh
```

5. Local runner test:
```bash
./scripts/slides_machine_runner.sh ./config/local.env
```

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

3. Test agent in foreground:
```bash
./scripts/slides_relay_agent.sh ./config/relay_agent.env
```

### 4) Test relay trigger
From controller machine:
```bash
./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
```

### 5) Bind Stream Deck key
Use `System -> Open` or `System -> Command` with:
```bash
cd '/Users/gmcgrath/Documents/Codex Test/ChatGPT Atlas Mod?' && ./scripts/slides_relay_streamdeck_trigger.sh ./config/relay_streamdeck.env
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
- Relay agent not triggering: verify `RELAY_URL`, `RELAY_SECRET`, and that `doGet` returns JSON with `ok:true`.
- Repeated triggering on startup: keep `FIRE_ON_STARTUP=0`.
- `Access Denied` in Chrome: the deck URL/account pair is not accessible in that Chrome profile. Open a deck that works in that profile and set `SLIDES_SOURCE_URL` to that URL.

## Global hotkey (while presenting)
If you want a keyboard hotkey that works even when Chrome is fullscreen:

1. Use the wrapper script:
```bash
./scripts/slides_hotkey_trigger.sh --mode local --config ./config/local.env
```

2. Install Hammerspoon:
```bash
brew install --cask hammerspoon
```

3. Copy the example config:
```bash
cp config/hammerspoon.init.lua.example ~/.hammerspoon/init.lua
```

4. Edit `~/.hammerspoon/init.lua`:
- Set `projectRoot` to your project path.
- Choose `triggerMode`:
  - `"local"` for this laptop only
  - `"relay"` for outbound-only dual-laptop trigger
  - `"ssh"` for direct SSH dual-laptop trigger
- Set `triggerConfig` to the matching config file.
- Pick your key combo (`hotkeyMods` + `hotkeyKey`).

5. Open Hammerspoon, grant Accessibility permission, and click `Reload Config`.

6. Press your hotkey (default in example: `ctrl+alt+cmd+r`).

Notes:
- Stream Deck can send the same hotkey if you prefer pressing a Stream Deck key.
- Logs are written to `/tmp/slides-hotkey.log`.
