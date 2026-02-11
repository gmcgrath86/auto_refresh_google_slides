#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  calibrate_notes_plus.sh [config_file]

What it does:
  1) Finds the Google Slides Presenter view window in Chrome.
  2) Prompts you to hover your mouse over the notes "+" button.
  3) Captures pointer coordinates and prints:
     - NOTES_PLUS_BUTTON_RIGHT_OFFSET
     - NOTES_PLUS_BUTTON_TOP_OFFSET

Optional:
  Provide a config file to source CHROME_APP from that file.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CONFIG_FILE="${1:-}"
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

CHROME_APP="${CHROME_APP:-Google Chrome}"

presenter_bounds="$(
  CHROME_APP_RUNTIME="$CHROME_APP" /usr/bin/osascript <<'APPLESCRIPT'
set chromeApp to system attribute "CHROME_APP_RUNTIME"
set boundsCsv to ""

using terms from application "Google Chrome"
  tell application chromeApp
    if (count of windows) is 0 then
      error "No Chrome windows open."
    end if

    set presenterIndex to missing value
    set totalWindows to count of windows

    repeat with i from 1 to totalWindows
      set oneTitle to ""
      set oneURL to ""
      try
        set oneTitle to title of active tab of window i
      end try
      try
        set oneURL to URL of active tab of window i
      end try

      if oneTitle contains "Presenter view" and oneURL starts with "about:blank" then
        set presenterIndex to i
        exit repeat
      end if
    end repeat

    if presenterIndex is missing value then
      set presenterIndex to 1
    end if

    set b to bounds of window presenterIndex
    set boundsCsv to (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text)
  end tell
end using terms from

return boundsCsv
APPLESCRIPT
)"

IFS=',' read -r win_left win_top win_right win_bottom <<<"$presenter_bounds"

if [[ -z "${win_left:-}" || -z "${win_top:-}" || -z "${win_right:-}" || -z "${win_bottom:-}" ]]; then
  echo "Unable to determine presenter window bounds." >&2
  exit 1
fi

echo "Presenter bounds: $presenter_bounds"
echo "Hover your mouse over the notes '+' button, then press Enter."
read -r _

mouse_position="$(
  swift - <<'SWIFT'
import CoreGraphics

if let event = CGEvent(source: nil) {
  let point = event.location
  print("\(Int(point.x)),\(Int(point.y))")
} else {
  fputs("Unable to read mouse location.\n", stderr)
  exit(1)
}
SWIFT
)"

IFS=',' read -r mouse_x mouse_y <<<"$mouse_position"

if [[ -z "${mouse_x:-}" || -z "${mouse_y:-}" ]]; then
  echo "Unable to determine mouse location." >&2
  exit 1
fi

right_offset=$(( win_right - mouse_x ))
top_offset=$(( mouse_y - win_top ))

echo
echo "Calibration result:"
echo "NOTES_PLUS_BUTTON_RIGHT_OFFSET=$right_offset"
echo "NOTES_PLUS_BUTTON_TOP_OFFSET=$top_offset"
echo
echo "Apply to config/local.env:"
echo "NOTES_PLUS_BUTTON_RIGHT_OFFSET=$right_offset"
echo "NOTES_PLUS_BUTTON_TOP_OFFSET=$top_offset"
