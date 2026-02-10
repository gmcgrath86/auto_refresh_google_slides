# Deploy Guide (Presentation Machines)

This guide gets this project running on one or two managed macOS presentation laptops quickly and repeatably.

## 1) Clone the repo
```bash
git clone https://github.com/gmcgrath86/auto_refresh_google_slides.git
cd auto_refresh_google_slides
```

## 2) Bootstrap machine files
```bash
./scripts/bootstrap_machine.sh --role presentation
```

That creates machine-local config files if missing and makes scripts executable.

To also install and wire the global hotkey in one shot:
```bash
./scripts/bootstrap_machine.sh --role presentation --install-hotkey
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

## 4) macOS permissions
Enable Accessibility for the app/process running automation:
- `System Settings -> Privacy & Security -> Accessibility`

If using Hammerspoon hotkey, enable:
- `Hammerspoon`

## 5) Validate local runner
```bash
./scripts/slides_machine_runner.sh ./config/local.env
```

Expected result:
- Slides fullscreen on extended display.
- Presenter notes fullscreen on mirrored/local display.

## 6) Hotkey setup (optional)
Recommended:
```bash
./scripts/bootstrap_machine.sh --role presentation --install-hotkey
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
