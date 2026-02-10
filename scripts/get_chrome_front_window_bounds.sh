#!/usr/bin/env bash
set -euo pipefail

CHROME_APP="${CHROME_APP:-Google Chrome}"

/usr/bin/osascript <<APPLESCRIPT
tell application "$CHROME_APP"
  if (count of windows) = 0 then
    error "No Chrome windows open."
  end if
  set b to bounds of front window
  set AppleScript's text item delimiters to ","
  return b as text
end tell
APPLESCRIPT
