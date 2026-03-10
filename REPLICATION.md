# Replication Runbook (for another Codex instance)

This runbook sets up a new macOS machine with:
- local refresh trigger,
- remote HTTP control,
- slide jump commands,
- notes font up/down commands,
- reliable notes font control via AXPress.

## 1) Clone or update repo
```bash
set -euo pipefail
REPO_DIR="$HOME/auto_refresh_google_slides"
REPO_URL="https://github.com/gmcgrath86/auto_refresh_google_slides.git"

if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only --tags
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
```

## 2) Bootstrap presentation machine + Hammerspoon
```bash
"$HOME/auto_refresh_google_slides/scripts/bootstrap_machine.sh" \
  --role presentation \
  --install-hotkey \
  --hotkey-mode local
```

If Homebrew is unavailable, install Hammerspoon manually:
- https://github.com/Hammerspoon/hammerspoon/releases/latest

## 3) Enforce required local config
```bash
set -euo pipefail
FILE="$HOME/auto_refresh_google_slides/config/local.env"

grep -q '^SLIDES_SOURCE_URL=' "$FILE" && sed -i '' 's|^SLIDES_SOURCE_URL=.*|SLIDES_SOURCE_URL=""|' "$FILE" || echo 'SLIDES_SOURCE_URL=""' >> "$FILE"
grep -q '^AUTO_CAPTURE_FRONT_TAB=' "$FILE" && sed -i '' 's|^AUTO_CAPTURE_FRONT_TAB=.*|AUTO_CAPTURE_FRONT_TAB=1|' "$FILE" || echo 'AUTO_CAPTURE_FRONT_TAB=1' >> "$FILE"
grep -q '^BOUNDS_MODE=' "$FILE" && sed -i '' 's|^BOUNDS_MODE=.*|BOUNDS_MODE="auto"|' "$FILE" || echo 'BOUNDS_MODE="auto"' >> "$FILE"
grep -q '^DISPLAY_ASSIGNMENT=' "$FILE" && sed -i '' 's|^DISPLAY_ASSIGNMENT=.*|DISPLAY_ASSIGNMENT="slides:extended,notes:desktop"|' "$FILE" || echo 'DISPLAY_ASSIGNMENT="slides:extended,notes:desktop"' >> "$FILE"
grep -q '^NOTES_PLUS_METHOD=' "$FILE" && sed -i '' 's|^NOTES_PLUS_METHOD=.*|NOTES_PLUS_METHOD="auto"|' "$FILE" || echo 'NOTES_PLUS_METHOD="auto"' >> "$FILE"
grep -q '^NOTES_PLUS_CLICK_STEPS=' "$FILE" && sed -i '' 's|^NOTES_PLUS_CLICK_STEPS=.*|NOTES_PLUS_CLICK_STEPS=7|' "$FILE" || echo 'NOTES_PLUS_CLICK_STEPS=7' >> "$FILE"
grep -q '^CHROME_FORCE_RENDERER_ACCESSIBILITY=' "$FILE" && sed -i '' 's|^CHROME_FORCE_RENDERER_ACCESSIBILITY=.*|CHROME_FORCE_RENDERER_ACCESSIBILITY=1|' "$FILE" || echo 'CHROME_FORCE_RENDERER_ACCESSIBILITY=1' >> "$FILE"
grep -q '^CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY=' "$FILE" && sed -i '' 's|^CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY=.*|CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY=1|' "$FILE" || echo 'CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY=1' >> "$FILE"
```

## 4) macOS permissions
Enable:
- `System Settings -> Privacy & Security -> Accessibility -> Hammerspoon`
- `System Settings -> Privacy & Security -> Accessibility -> Terminal` (or whichever shell host is running scripts)

## 5) Reload Hammerspoon
```bash
open -a Hammerspoon
hs -c 'hs.reload()'
```

## 6) Validate local execution
```bash
"$HOME/auto_refresh_google_slides/scripts/slides_machine_runner.sh" \
  "$HOME/auto_refresh_google_slides/config/local.env"
```

Expected:
- slides fullscreen on extended display,
- notes fullscreen on mirrored/desktop display,
- notes font bumped by 7 clicks.

## 7) Validate remote HTTP commands
```bash
IP="$(ipconfig getifaddr en0)"

curl "http://$IP:8765/slides/health"
curl "http://$IP:8765/slides/run"
curl "http://$IP:8765/slides/jump/25"
curl "http://$IP:8765/slides/notes/font/up/7"
curl "http://$IP:8765/slides/notes/font/down/3"
curl "http://$IP:8765/slides/notes/font?dir=up&steps=2"
```

## 8) Fast troubleshooting
```bash
tail -n 100 /tmp/slides-hotkey.log
```

Look for:
- `NOTES_METHOD_USED=ax`
- `NOTES_CLICK_DETAIL=clicked:...:source=axpress`

