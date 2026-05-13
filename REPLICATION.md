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
  --install-launch-agent \
  --hotkey-mode local \
  --http-interface en18,en0
```

Use `--http-interface en18,en0` when wired Ethernet should be primary and Wi-Fi should be backup. The generated Hammerspoon config binds to the first interface in the list with an IPv4 address and periodically switches back to the earlier interface if it returns.

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
IP="$(ipconfig getifaddr en18 || ipconfig getifaddr en0)"

curl "http://$IP:8765/slides/health"
curl "http://$IP:8765/slides/run"
curl "http://$IP:8765/slides/load?presentation_id=<DECK_ID>&title=April%20All%20Hands"
curl "http://$IP:8765/keynote/health"
curl "http://$IP:8765/keynote/load?icloud_relative_path=Events/April%20All%20Hands.key&mode=present"
curl "http://$IP:8765/keynote/goto?slide=12"
curl "http://$IP:8765/slides/status"
curl "http://$IP:8765/slides/jump/25"
curl "http://$IP:8765/slides/kill-all"
curl "http://$IP:8765/slides/notes/font/up/7"
curl "http://$IP:8765/slides/notes/font/down/3"
curl "http://$IP:8765/slides/notes/font?dir=up&steps=2"
```

Expected HTTP health on the current presentation machine:
- active interface: `en18`
- active address: `10.2.130.64`
- interface priority: `["en18","en0"]`

Expected Keynote behavior:
- `.key` files are resolved under `~/Library/Mobile Documents/com~apple~CloudDocs`.
- Keynote is detected by bundle id `com.apple.Keynote`; this supports both `/Applications/Keynote.app` and the current `/Applications/Keynote Creator Studio.app` bundle path.
- Before `mode=present` starts playback, the Keynote document is reset to the requested `slide` number (default `1`) and its window is moved to the extended display so the full-screen slide output uses the extended display. Presenter notes stay on the desktop/mirrored display.
- `/keynote/goto` jumps the active Keynote document to a requested slide.
- `/slides/kill-all` closes open Keynote documents plus Google Slides presentation/notes Chrome tabs while leaving unrelated Chrome tabs alone.
- `mode=present` only returns success after Hammerspoon can see Keynote windows on the expected slide and notes displays. If the presenter side does not materialize, `/keynote/load` fails with `presenter-display-not-ready:...` instead of claiming success.
- AppleScript failures are flattened into readable error text rather than opaque Lua table pointer strings.

## 8) Fast troubleshooting
```bash
tail -n 100 /tmp/slides-hotkey.log
```

Look for:
- `NOTES_METHOD_USED=ax`
- `NOTES_CLICK_DETAIL=clicked:...:source=axpress` or `source=coords-fallback`

## 9) Local commit stack and fallback

As of the tested presentation-machine state, the local branch contains these commits on top of `origin/main`:
```text
a68655b Keep audience URL repair before presenter notes
d2f3067 Add Keynote iCloud load endpoint
9bb2ba3 Target Apple Keynote by bundle id
24014c2 Arrange Keynote playback on extended display
1174c43 Support wired-first HTTP interface fallback
e4a7046 Fix HTTP interface address lookup path
```

Operationally tested behavior:
- `/slides/load` works on the wired interface.
- `/slides/run` is asynchronous and returns `202 Accepted`; poll the returned `/slides/status/<runId>` path until the state is `succeeded` or `failed`.
- `/keynote/load` works on the wired interface and reports the selected slide and notes displays in the `detail` field when `mode=open` is used.

Fallback plan if the local stack causes issues:
```bash
cd "$HOME/auto_refresh_google_slides"
git fetch --tags origin
git switch main
git reset --hard origin/main
"$HOME/auto_refresh_google_slides/scripts/bootstrap_machine.sh" \
  --role presentation \
  --install-hotkey \
  --install-launch-agent \
  --hotkey-mode local \
  --http-interface en18
```

That reverts to the last GitHub `main` behavior and removes the local Keynote endpoint, Keynote display arrangement, and wired-first fallback changes. If only the wired fallback is suspect, reinstall the current local checkout with `--http-interface en18` instead of `--http-interface en18,en0`.
