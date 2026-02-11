#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  slides_machine_runner.sh [config_file]

Input URL options:
  - Provide SLIDES_PRESENT_URL directly, OR
  - Provide SLIDES_SOURCE_URL (edit/present URL), OR
  - Set AUTO_CAPTURE_FRONT_TAB=1 to read URL from active Chrome tab.

Optional config variables:
  CHROME_APP="Google Chrome"
  CHROME_PROFILE="Default"
  BOUNDS_MODE="auto"
  DISPLAY_ASSIGNMENT="slides:rightmost,notes:leftmost"
  PRIMARY_BOUNDS="0,25,1920,1080"
  NOTES_BOUNDS="1920,25,3840,1080"
  FULLSCREEN_PRIMARY=1
  FULLSCREEN_NOTES=1
  EXIT_EXISTING_FULLSCREEN=1
  CLOSE_EXISTING_PRESENTATION_WINDOWS=1
  CLOSE_EXISTING_WINDOWS=0
  FORCE_KILL_CHROME=0
  CACHE_BUST=1
  AUTO_CAPTURE_FRONT_TAB=1
  LAUNCH_FROM_EDIT_MODE=0
  KEEP_SOURCE_TAB_OPEN=1
  USE_PRESENTER_NOTES_SHORTCUT=1
  LAUNCH_DELAY_SECONDS=1.0
  PRESENTER_READY_DELAY_SECONDS=5.0
  NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS=0.5
  NOTES_SHORTCUT_MAX_WAIT_SECONDS=20
  NOTES_PLUS_CLICK_STEPS=0
  NOTES_PLUS_METHOD="auto"
  NOTES_PLUS_READY_DELAY_SECONDS=0.45
  NOTES_PLUS_CLICK_DELAY_SECONDS=0.08
  NOTES_PLUS_BUTTON_RIGHT_OFFSET=56
  NOTES_PLUS_BUTTON_TOP_OFFSET=164
  OPEN_RETRY_COUNT=3
  OPEN_RETRY_DELAY_SECONDS=1.0
  WINDOW_WAIT_TIMEOUT_SECONDS=20
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
CHROME_PROFILE="${CHROME_PROFILE:-Default}"
BOUNDS_MODE="${BOUNDS_MODE:-auto}"
DISPLAY_ASSIGNMENT="${DISPLAY_ASSIGNMENT:-slides:rightmost,notes:leftmost}"
PRIMARY_BOUNDS="${PRIMARY_BOUNDS:-0,25,1920,1080}"
NOTES_BOUNDS="${NOTES_BOUNDS:-1920,25,3840,1080}"
FULLSCREEN_PRIMARY="${FULLSCREEN_PRIMARY:-1}"
FULLSCREEN_NOTES="${FULLSCREEN_NOTES:-1}"
EXIT_EXISTING_FULLSCREEN="${EXIT_EXISTING_FULLSCREEN:-1}"
CLOSE_EXISTING_PRESENTATION_WINDOWS="${CLOSE_EXISTING_PRESENTATION_WINDOWS:-1}"
CLOSE_EXISTING_WINDOWS="${CLOSE_EXISTING_WINDOWS:-0}"
FORCE_KILL_CHROME="${FORCE_KILL_CHROME:-0}"
CACHE_BUST="${CACHE_BUST:-1}"
AUTO_CAPTURE_FRONT_TAB="${AUTO_CAPTURE_FRONT_TAB:-1}"
LAUNCH_FROM_EDIT_MODE="${LAUNCH_FROM_EDIT_MODE:-0}"
KEEP_SOURCE_TAB_OPEN="${KEEP_SOURCE_TAB_OPEN:-1}"
USE_PRESENTER_NOTES_SHORTCUT="${USE_PRESENTER_NOTES_SHORTCUT:-1}"
LAUNCH_DELAY_SECONDS="${LAUNCH_DELAY_SECONDS:-1.0}"
PRESENTER_READY_DELAY_SECONDS="${PRESENTER_READY_DELAY_SECONDS:-5.0}"
NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS="${NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS:-0.5}"
NOTES_PLUS_CLICK_STEPS="${NOTES_PLUS_CLICK_STEPS:-${NOTES_ZOOM_STEPS:-0}}"
NOTES_PLUS_METHOD="${NOTES_PLUS_METHOD:-auto}"
NOTES_PLUS_READY_DELAY_SECONDS="${NOTES_PLUS_READY_DELAY_SECONDS:-0.45}"
NOTES_PLUS_CLICK_DELAY_SECONDS="${NOTES_PLUS_CLICK_DELAY_SECONDS:-${NOTES_ZOOM_STEP_DELAY_SECONDS:-0.08}}"
NOTES_PLUS_BUTTON_RIGHT_OFFSET="${NOTES_PLUS_BUTTON_RIGHT_OFFSET:-56}"
NOTES_PLUS_BUTTON_TOP_OFFSET="${NOTES_PLUS_BUTTON_TOP_OFFSET:-164}"
OPEN_RETRY_COUNT="${OPEN_RETRY_COUNT:-3}"
OPEN_RETRY_DELAY_SECONDS="${OPEN_RETRY_DELAY_SECONDS:-1.0}"
WINDOW_WAIT_TIMEOUT_SECONDS="${WINDOW_WAIT_TIMEOUT_SECONDS:-20}"
NOTES_SHORTCUT_MAX_WAIT_SECONDS="${NOTES_SHORTCUT_MAX_WAIT_SECONDS:-$WINDOW_WAIT_TIMEOUT_SECONDS}"

SLIDES_PRESENT_URL="${SLIDES_PRESENT_URL:-}"
SLIDES_NOTES_URL="${SLIDES_NOTES_URL:-}"
SLIDES_SOURCE_URL="${SLIDES_SOURCE_URL:-}"
SLIDES_LAUNCH_URL=""
SOURCE_DECK_ID=""
DISPLAY_COUNT=""
BOUNDS_SOURCE=""

if [[ "$BOUNDS_MODE" != "auto" && "$BOUNDS_MODE" != "manual" ]]; then
  echo "Invalid BOUNDS_MODE=$BOUNDS_MODE (expected auto or manual)" >&2
  exit 1
fi

if [[ "$NOTES_PLUS_METHOD" != "auto" && "$NOTES_PLUS_METHOD" != "js" && "$NOTES_PLUS_METHOD" != "coords" ]]; then
  echo "Invalid NOTES_PLUS_METHOD=$NOTES_PLUS_METHOD (expected auto, js, or coords)" >&2
  exit 1
fi

append_cache_buster() {
  local url="$1"
  local stamp="$2"

  if [[ "$url" == *"?"* ]]; then
    printf '%s&codex_refresh=%s\n' "$url" "$stamp"
  else
    printf '%s?codex_refresh=%s\n' "$url" "$stamp"
  fi
}

capture_front_tab_url() {
  local direct_url
  local any_slides_url
  local copied_url

  direct_url="$(
    /usr/bin/osascript <<APPLESCRIPT 2>/dev/null || true
tell application "$CHROME_APP"
  if (count of windows) > 0 then
    return URL of active tab of front window
  end if
end tell
APPLESCRIPT
  )"
  direct_url="$(printf '%s' "$direct_url" | tr -d '\r\n')"

  if [[ "$direct_url" =~ ^https?:// && "$direct_url" == *"docs.google.com/presentation/d/"* ]]; then
    printf '%s\n' "$direct_url"
    return 0
  fi

  any_slides_url="$(
    /usr/bin/osascript <<APPLESCRIPT 2>/dev/null || true
tell application "$CHROME_APP"
  if (count of windows) > 0 then
    repeat with oneWindow in windows
      repeat with oneTab in tabs of oneWindow
        try
          set oneUrl to URL of oneTab
          if oneUrl contains "docs.google.com/presentation/d/" then
            return oneUrl
          end if
        end try
      end repeat
    end repeat
  end if
end tell
APPLESCRIPT
  )"
  any_slides_url="$(printf '%s' "$any_slides_url" | tr -d '\r\n')"

  if [[ "$any_slides_url" =~ ^https?:// ]]; then
    printf '%s\n' "$any_slides_url"
    return 0
  fi

  open -a "$CHROME_APP"
  sleep 0.4

  /usr/bin/osascript <<APPLESCRIPT
 tell application "System Events"
   tell process "$CHROME_APP"
     set frontmost to true
     keystroke "l" using {command down}
     delay 0.15
     keystroke "c" using {command down}
   end tell
 end tell
APPLESCRIPT

  sleep 0.15
  copied_url="$(pbpaste | tr -d '\r\n')"

  if [[ "$copied_url" =~ ^https?:// && "$copied_url" == *"docs.google.com/presentation/d/"* ]]; then
    printf '%s\n' "$copied_url"
    return 0
  fi

  return 1
}

derive_present_url() {
  local source_url="$1"
  local deck_id=""
  local slide_id=""
  local present_url=""

  if [[ "$source_url" =~ /presentation/d/([^/?#]+) ]]; then
    deck_id="${BASH_REMATCH[1]}"
  else
    return 1
  fi

  if [[ "$source_url" =~ /presentation/d/[^/?#]+/present([/?#]|$) ]]; then
    present_url="$source_url"
  else
    present_url="https://docs.google.com/presentation/d/$deck_id/present"
  fi

  if [[ "$source_url" =~ slide=([^&#]+) && "$present_url" != *"slide="* ]]; then
    slide_id="${BASH_REMATCH[1]}"
    if [[ "$present_url" == *"?"* ]]; then
      present_url+="&slide=$slide_id"
    else
      present_url+="?slide=$slide_id"
    fi
  fi

  printf '%s\n' "$present_url"
}

derive_source_url() {
  local input_url="$1"
  local deck_id=""
  local slide_id=""
  local source_url=""

  if [[ "$input_url" =~ /presentation/d/([^/?#]+) ]]; then
    deck_id="${BASH_REMATCH[1]}"
  else
    return 1
  fi

  source_url="https://docs.google.com/presentation/d/$deck_id/edit"

  if [[ "$input_url" =~ slide=([^&#]+) ]]; then
    slide_id="${BASH_REMATCH[1]}"
    source_url+="?slide=$slide_id"
  fi

  printf '%s\n' "$source_url"
}

ensure_show_notes_param() {
  local url="$1"

  if [[ "$url" == *"showNotes="* ]]; then
    printf '%s\n' "$url"
    return 0
  fi

  if [[ "$url" == *"?"* ]]; then
    printf '%s&showNotes=true\n' "$url"
  else
    printf '%s?showNotes=true\n' "$url"
  fi
}

resolve_runtime_bounds() {
  local swift_out=""
  local line key value
  local resolved_slides=""
  local resolved_notes=""
  local resolved_count=""
  local resolved_source=""

  swift_out="$(
    BOUNDS_MODE_RUNTIME="$BOUNDS_MODE" \
    DISPLAY_ASSIGNMENT_RUNTIME="$DISPLAY_ASSIGNMENT" \
    PRIMARY_BOUNDS_RUNTIME="$PRIMARY_BOUNDS" \
    NOTES_BOUNDS_RUNTIME="$NOTES_BOUNDS" \
    swift - <<\SWIFT
import AppKit
import Foundation

struct Bounds {
  var left: Int
  var top: Int
  var right: Int
  var bottom: Int

  var width: Int { right - left }
  var height: Int { bottom - top }

  func csv() -> String {
    "\(left),\(top),\(right),\(bottom)"
  }
}

func parseBounds(_ csv: String) -> Bounds? {
  let trimmed = csv.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return nil }

  let pieces = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  if pieces.count != 4 { return nil }

  guard
    let left = Int(pieces[0]),
    let top = Int(pieces[1]),
    let right = Int(pieces[2]),
    let bottom = Int(pieces[3]),
    right > left,
    bottom > top
  else {
    return nil
  }

  return Bounds(left: left, top: top, right: right, bottom: bottom)
}

func intersectionArea(_ a: Bounds, _ b: Bounds) -> Int {
  let interLeft = max(a.left, b.left)
  let interTop = max(a.top, b.top)
  let interRight = min(a.right, b.right)
  let interBottom = min(a.bottom, b.bottom)

  let width = max(0, interRight - interLeft)
  let height = max(0, interBottom - interTop)
  return width * height
}

func centerDistanceSquared(_ a: Bounds, _ b: Bounds) -> Double {
  let ax = Double(a.left + a.right) / 2.0
  let ay = Double(a.top + a.bottom) / 2.0
  let bx = Double(b.left + b.right) / 2.0
  let by = Double(b.top + b.bottom) / 2.0
  let dx = ax - bx
  let dy = ay - by
  return (dx * dx) + (dy * dy)
}

func clampBounds(_ input: Bounds, to screens: [Bounds]) -> Bounds {
  if screens.isEmpty { return input }

  var selected = screens[0]
  var bestArea = -1

  for screen in screens {
    let area = intersectionArea(input, screen)
    if area > bestArea {
      bestArea = area
      selected = screen
    }
  }

  if bestArea <= 0 {
    selected = screens.min(by: { centerDistanceSquared(input, $0) < centerDistanceSquared(input, $1) }) ?? selected
  }

  let screenWidth = max(1, selected.width)
  let screenHeight = max(1, selected.height)

  var targetWidth = input.width
  var targetHeight = input.height
  if targetWidth <= 0 { targetWidth = screenWidth }
  if targetHeight <= 0 { targetHeight = screenHeight }

  targetWidth = min(targetWidth, screenWidth)
  targetHeight = min(targetHeight, screenHeight)

  let maxLeft = selected.right - targetWidth
  let maxTop = selected.bottom - targetHeight

  let clampedLeft = min(max(input.left, selected.left), maxLeft)
  let clampedTop = min(max(input.top, selected.top), maxTop)

  return Bounds(
    left: clampedLeft,
    top: clampedTop,
    right: clampedLeft + targetWidth,
    bottom: clampedTop + targetHeight
  )
}

func visibleBoundsForScreen(_ screen: NSScreen) -> Bounds {
  let frame = screen.frame
  let visible = screen.visibleFrame

  let left = Int(round(visible.minX))
  let right = Int(round(visible.maxX))
  let top = Int(round(frame.maxY - visible.maxY))
  let bottom = Int(round(frame.maxY - visible.minY))

  return Bounds(left: left, top: top, right: right, bottom: bottom)
}

func parseAssignment(_ assignment: String) -> (slides: String, notes: String) {
  var slides = "rightmost"
  var notes = "leftmost"

  for chunk in assignment.split(separator: ",") {
    let pair = chunk.split(separator: ":", maxSplits: 1)
    if pair.count != 2 { continue }
    let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if key == "slides" { slides = value }
    if key == "notes" { notes = value }
  }

  return (slides, notes)
}

func pickScreen(named token: String, screens: [Bounds], main: Bounds) -> Bounds {
  if screens.isEmpty { return main }
  let lowered = token.lowercased()
  switch lowered {
  case "leftmost":
    return screens.min(by: { $0.left < $1.left }) ?? main
  case "rightmost":
    return screens.max(by: { $0.left < $1.left }) ?? main
  case "primary", "main":
    return main
  default:
    return main
  }
}

let env = ProcessInfo.processInfo.environment
let modeRaw = (env["BOUNDS_MODE_RUNTIME"] ?? "auto").lowercased()
let mode = (modeRaw == "manual") ? "manual" : "auto"
let assignment = env["DISPLAY_ASSIGNMENT_RUNTIME"] ?? "slides:rightmost,notes:leftmost"
let manualPrimary = env["PRIMARY_BOUNDS_RUNTIME"] ?? ""
let manualNotes = env["NOTES_BOUNDS_RUNTIME"] ?? ""

let screens = NSScreen.screens
if screens.isEmpty {
  fputs("No displays detected by NSScreen.\n", stderr)
  exit(1)
}

let visibleScreens = screens.map { visibleBoundsForScreen($0) }
let mainVisible = visibleBoundsForScreen(NSScreen.main ?? screens[0])
let displayCount = visibleScreens.count

let assignmentTokens = parseAssignment(assignment)
var slidesCandidate: Bounds
var notesCandidate: Bounds

if displayCount <= 1 {
  slidesCandidate = mainVisible
  notesCandidate = mainVisible
} else {
  slidesCandidate = pickScreen(named: assignmentTokens.slides, screens: visibleScreens, main: mainVisible)
  notesCandidate = pickScreen(named: assignmentTokens.notes, screens: visibleScreens, main: mainVisible)
}

var sourceLabel = "auto"
if mode == "manual" {
  sourceLabel = "manual_clamped"
  if let parsed = parseBounds(manualPrimary) {
    slidesCandidate = parsed
  }
  if let parsed = parseBounds(manualNotes) {
    notesCandidate = parsed
  }
}

let slidesFinal = clampBounds(slidesCandidate, to: visibleScreens)
let notesFinal = clampBounds(notesCandidate, to: visibleScreens)

print("DISPLAY_COUNT=\(displayCount)")
print("BOUNDS_SOURCE=\(sourceLabel)")
print("SLIDES_BOUNDS=\(slidesFinal.csv())")
print("NOTES_BOUNDS=\(notesFinal.csv())")
SWIFT
  )"

  while IFS='=' read -r key value; do
    case "$key" in
      DISPLAY_COUNT) resolved_count="$value" ;;
      BOUNDS_SOURCE) resolved_source="$value" ;;
      SLIDES_BOUNDS) resolved_slides="$value" ;;
      NOTES_BOUNDS) resolved_notes="$value" ;;
    esac
  done <<< "$swift_out"

  if [[ -z "$resolved_slides" || -z "$resolved_notes" || -z "$resolved_count" ]]; then
    echo "Failed to resolve runtime bounds." >&2
    echo "$swift_out" >&2
    exit 1
  fi

  PRIMARY_BOUNDS="$resolved_slides"
  NOTES_BOUNDS="$resolved_notes"
  DISPLAY_COUNT="$resolved_count"
  BOUNDS_SOURCE="${resolved_source:-auto}"
}

if [[ -z "$SLIDES_SOURCE_URL" && "$AUTO_CAPTURE_FRONT_TAB" == "1" ]]; then
  SLIDES_SOURCE_URL="$(capture_front_tab_url || true)"
fi

if [[ -n "$SLIDES_SOURCE_URL" && "$SLIDES_SOURCE_URL" =~ /presentation/d/[^/?#]+/present([/?#]|$) ]]; then
  SLIDES_SOURCE_URL="$(derive_source_url "$SLIDES_SOURCE_URL" || true)"
fi

if [[ -z "$SLIDES_SOURCE_URL" && -n "$SLIDES_PRESENT_URL" ]]; then
  SLIDES_SOURCE_URL="$(derive_source_url "$SLIDES_PRESENT_URL" || true)"
fi

if [[ -z "$SLIDES_PRESENT_URL" && -n "$SLIDES_SOURCE_URL" ]]; then
  SLIDES_PRESENT_URL="$(derive_present_url "$SLIDES_SOURCE_URL" || true)"
fi

if [[ "$LAUNCH_FROM_EDIT_MODE" == "1" && -n "$SLIDES_SOURCE_URL" ]]; then
  SLIDES_LAUNCH_URL="$(ensure_show_notes_param "$SLIDES_SOURCE_URL")"
else
  SLIDES_LAUNCH_URL="$SLIDES_PRESENT_URL"
fi

if [[ -n "$SLIDES_SOURCE_URL" && "$SLIDES_SOURCE_URL" =~ /presentation/d/([^/?#]+) ]]; then
  SOURCE_DECK_ID="${BASH_REMATCH[1]}"
fi

if [[ -z "$SLIDES_LAUNCH_URL" ]]; then
  echo "Unable to determine launch URL. Set SLIDES_SOURCE_URL, SLIDES_PRESENT_URL, or enable AUTO_CAPTURE_FRONT_TAB." >&2
  exit 1
fi

if [[ -n "$SLIDES_NOTES_URL" ]]; then
  USE_PRESENTER_NOTES_SHORTCUT=0
fi

if [[ "$CACHE_BUST" == "1" ]]; then
  ts="$(date +%s)"
  SLIDES_LAUNCH_URL="$(append_cache_buster "$SLIDES_LAUNCH_URL" "$ts")"
  if [[ -n "$SLIDES_NOTES_URL" ]]; then
    SLIDES_NOTES_URL="$(append_cache_buster "$SLIDES_NOTES_URL" "$ts")"
  fi
fi

resolve_runtime_bounds
echo "[slides_machine_runner] bounds source=$BOUNDS_SOURCE displays=$DISPLAY_COUNT slides=$PRIMARY_BOUNDS notes=$NOTES_BOUNDS"

export CHROME_APP
export BOUNDS_MODE
export DISPLAY_ASSIGNMENT
export PRIMARY_BOUNDS
export NOTES_BOUNDS
export FULLSCREEN_PRIMARY
export FULLSCREEN_NOTES
export LAUNCH_FROM_EDIT_MODE
export KEEP_SOURCE_TAB_OPEN
export USE_PRESENTER_NOTES_SHORTCUT
export LAUNCH_DELAY_SECONDS
export PRESENTER_READY_DELAY_SECONDS
export NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS
export NOTES_SHORTCUT_MAX_WAIT_SECONDS
export NOTES_PLUS_CLICK_STEPS
export NOTES_PLUS_METHOD
export NOTES_PLUS_READY_DELAY_SECONDS
export NOTES_PLUS_CLICK_DELAY_SECONDS
export NOTES_PLUS_BUTTON_RIGHT_OFFSET
export NOTES_PLUS_BUTTON_TOP_OFFSET
export WINDOW_WAIT_TIMEOUT_SECONDS

open_chrome_window() {
  local target_url="$1"

  if ! CHROME_APP_RUNTIME="$CHROME_APP" CHROME_TARGET_URL="$target_url" /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1
set chromeApp to system attribute "CHROME_APP_RUNTIME"
set targetUrl to system attribute "CHROME_TARGET_URL"

using terms from application "Google Chrome"
  tell application chromeApp
    activate
    if (count of windows) is greater than 0 then
      tell front window
        set newTab to make new tab with properties {URL:targetUrl}
        set active tab index to (count of tabs)
      end tell
    else
      set newWindow to make new window
      set URL of active tab of newWindow to targetUrl
    end if
  end tell
end using terms from
APPLESCRIPT
  then
    # Fallback for environments where Chrome AppleScript APIs are restricted.
    open -a "$CHROME_APP" "$target_url"
  fi
}

wait_for_chrome_process() {
  local max_wait_seconds="${1:-5}"
  local started_at
  started_at="$(date +%s)"

  while true; do
    if pgrep -x "$CHROME_APP" >/dev/null 2>&1; then
      return 0
    fi

    if (( "$(date +%s)" - started_at >= max_wait_seconds )); then
      return 1
    fi

    sleep 0.1
  done
}

open_chrome_window_with_retry() {
  local target_url="$1"
  local attempt

  for (( attempt=1; attempt<=OPEN_RETRY_COUNT; attempt++ )); do
    open_chrome_window "$target_url" || true

    if wait_for_chrome_process 6; then
      return 0
    fi

    sleep "$OPEN_RETRY_DELAY_SECONDS"
  done

  echo "Chrome did not become available after $OPEN_RETRY_COUNT attempts." >&2
  return 1
}

close_existing_presentation_windows() {
  if [[ "$CLOSE_EXISTING_PRESENTATION_WINDOWS" != "1" ]]; then
    return 0
  fi

  CHROME_APP_RUNTIME="$CHROME_APP" /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
set chromeApp to system attribute "CHROME_APP_RUNTIME"

using terms from application "Google Chrome"
  tell application chromeApp
    set totalWindows to count of windows
    if totalWindows is 0 then
      return
    end if

    repeat with i from totalWindows to 1 by -1
      set oneTitle to ""
      set oneURL to ""
      set shouldClose to false

      try
        set oneTitle to title of active tab of window i
      end try

      try
        set oneURL to URL of active tab of window i
      end try

      if oneURL contains "/presentation/d/" and oneURL contains "/present" then
        set shouldClose to true
      end if

      if oneTitle contains "Presenter view" then
        set shouldClose to true
      end if

      if oneTitle contains "Who's using Chrome?" then
        set shouldClose to true
      end if

      if oneURL starts with "chrome://profile-picker" then
        set shouldClose to true
      end if

      if shouldClose then
        try
          close window i
        end try
      end if
    end repeat
  end tell
end using terms from
APPLESCRIPT
}

ensure_source_tab_open() {
  if [[ "$KEEP_SOURCE_TAB_OPEN" != "1" || -z "$SLIDES_SOURCE_URL" ]]; then
    return 0
  fi

  CHROME_APP_RUNTIME="$CHROME_APP" CHROME_SOURCE_URL="$SLIDES_SOURCE_URL" CHROME_SOURCE_DECK_ID="$SOURCE_DECK_ID" /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
set chromeApp to system attribute "CHROME_APP_RUNTIME"
set sourceUrl to system attribute "CHROME_SOURCE_URL"
set sourceDeckId to system attribute "CHROME_SOURCE_DECK_ID"

using terms from application "Google Chrome"
  tell application chromeApp
    activate

    if (count of windows) is 0 then
      set newWindow to make new window
      set URL of active tab of newWindow to sourceUrl
      return
    end if

    set foundDeckEditTab to false

    repeat with oneWindow in windows
      set tabCount to count of tabs of oneWindow

      repeat with tabIndex from 1 to tabCount
        set tabUrl to ""

        try
          set tabUrl to URL of tab tabIndex of oneWindow
        end try

        if sourceDeckId is not "" then
          if tabUrl contains ("/presentation/d/" & sourceDeckId & "/") and tabUrl contains "/edit" then
            set foundDeckEditTab to true
            exit repeat
          end if
        else
          if tabUrl starts with sourceUrl then
            set foundDeckEditTab to true
            exit repeat
          end if
        end if
      end repeat

      if foundDeckEditTab then
        exit repeat
      end if
    end repeat

    if foundDeckEditTab is false then
      tell front window
        set newTab to make new tab with properties {URL:sourceUrl}
      end tell
    end if
  end tell
end using terms from
APPLESCRIPT
}

# Optional: exit fullscreen on existing windows before relaunching.
if [[ "$EXIT_EXISTING_FULLSCREEN" == "1" ]]; then
  /usr/bin/osascript <<APPLESCRIPT || true
   tell application "System Events"
     if exists process "$CHROME_APP" then
       tell process "$CHROME_APP"
         repeat with oneWindow in windows
           try
             if value of attribute "AXFullScreen" of oneWindow is true then
               set value of attribute "AXFullScreen" of oneWindow to false
               delay 0.1
             end if
           end try
         end repeat
       end tell
     end if
   end tell
APPLESCRIPT
fi

close_existing_presentation_windows
ensure_source_tab_open

if [[ "$CLOSE_EXISTING_WINDOWS" == "1" ]]; then
  /usr/bin/osascript <<APPLESCRIPT || true
   tell application "System Events"
     if exists process "$CHROME_APP" then
       tell process "$CHROME_APP"
         set frontmost to true
         repeat 120 times
           if (count of windows) is 0 then
             exit repeat
           end if
           keystroke "w" using {command down, shift down}
           delay 0.05
         end repeat
       end tell
     end if
   end tell
APPLESCRIPT

  if [[ "$FORCE_KILL_CHROME" == "1" ]]; then
    pkill -x "$CHROME_APP" >/dev/null 2>&1 || true
    sleep 0.5
  fi
fi

open_chrome_window_with_retry "$SLIDES_LAUNCH_URL"
sleep "$LAUNCH_DELAY_SECONDS"

if [[ -n "$SLIDES_NOTES_URL" ]]; then
  open_chrome_window_with_retry "$SLIDES_NOTES_URL"
  sleep "$LAUNCH_DELAY_SECONDS"
fi

export EXPECT_NOTES_WINDOW
if [[ -n "$SLIDES_NOTES_URL" || "$USE_PRESENTER_NOTES_SHORTCUT" == "1" ]]; then
  EXPECT_NOTES_WINDOW=1
else
  EXPECT_NOTES_WINDOW=0
fi

apple_summary="$(
/usr/bin/osascript <<\APPLESCRIPT
on csvToBounds(csvText)
  set oldDelims to text item delimiters of AppleScript
  set text item delimiters of AppleScript to ","
  set rawParts to text items of csvText
  set text item delimiters of AppleScript to oldDelims

  if (count of rawParts) is not 4 then
    error "Bounds must be 4 comma-separated integers: " & csvText
  end if

  set outList to {}
  repeat with onePart in rawParts
    set end of outList to (onePart as integer)
  end repeat

  return outList
end csvToBounds

on startsWith(valueText, prefixText)
  set valueLength to length of valueText
  set prefixLength to length of prefixText
  if prefixLength is greater than valueLength then return false
  if prefixLength is 0 then return true
  return (text 1 thru prefixLength of valueText) is prefixText
end startsWith

on clickWindowCenter(processName, targetWindow)
  tell application "System Events"
    tell process processName
      set winPos to value of attribute "AXPosition" of targetWindow
      set winSize to value of attribute "AXSize" of targetWindow
    end tell
  end tell

  set clickX to (item 1 of winPos) + ((item 1 of winSize) div 2)
  set clickY to (item 2 of winPos) + ((item 2 of winSize) div 2)

  tell application "System Events"
    tell process processName
      set frontmost to true
      click at {clickX, clickY}
    end tell
  end tell
end clickWindowCenter

on clickFrontWindowCenter(processName)
  tell application "System Events"
    tell process processName
      if (count of windows) is 0 then
        return false
      end if
      set frontWindowRef to window 1
      set winPos to value of attribute "AXPosition" of frontWindowRef
      set winSize to value of attribute "AXSize" of frontWindowRef
    end tell
  end tell

  set clickX to (item 1 of winPos) + ((item 1 of winSize) div 2)
  set clickY to (item 2 of winPos) + ((item 2 of winSize) div 2)

  tell application "System Events"
    tell process processName
      set frontmost to true
      click at {clickX, clickY}
    end tell
  end tell

  return true
end clickFrontWindowCenter

on waitForWindowCount(processName, minCount, timeoutSeconds)
  set startedAt to current date

  repeat
    set currentCount to 0
    try
      tell application "System Events"
        tell process processName
          set currentCount to count of windows
        end tell
      end tell
    end try

    if currentCount is greater than or equal to minCount then return

    if (current date) - startedAt > timeoutSeconds then
      error "Timed out waiting for " & minCount & " Chrome window(s)."
    end if

    delay 0.1
  end repeat
end waitForWindowCount

on hasNotesChromeWindow(chromeAppName)
  using terms from application "Google Chrome"
    tell application chromeAppName
      set chromeWindowCount to count of windows
      repeat with i from 1 to chromeWindowCount
        set oneTitle to ""
        set oneURL to ""

        try
          set oneTitle to title of active tab of window i
        end try

        try
          set oneURL to URL of active tab of window i
        end try

        if my isNotesChromeWindow(oneTitle, oneURL) then
          return true
        end if
      end repeat
    end tell
  end using terms from

  return false
end hasNotesChromeWindow

on waitForNotesChromeWindow(chromeAppName, timeoutSeconds)
  set startedAt to current date

  repeat
    if my hasNotesChromeWindow(chromeAppName) then return true

    if (current date) - startedAt > timeoutSeconds then return false
    delay 0.1
  end repeat
end waitForNotesChromeWindow

on isNotesChromeWindow(oneTitle, oneURL)
  if oneTitle contains "Presenter view" then return true
  if oneURL contains "presenter=true" then return true
  if oneURL contains "/presenter" then return true
  return false
end isNotesChromeWindow

on triggerNotesShortcutWithRetries(processName, chromeAppName, maxWaitSeconds, retryIntervalSeconds)
  set startedAt to current date

  repeat
    if my hasNotesChromeWindow(chromeAppName) then return true

    my clickFrontWindowCenter(processName)
    tell application "System Events"
      tell process processName
        set frontmost to true
        keystroke "s"
      end tell
    end tell

    delay retryIntervalSeconds

    if my hasNotesChromeWindow(chromeAppName) then return true
    if (current date) - startedAt > maxWaitSeconds then return false
  end repeat
end triggerNotesShortcutWithRetries

on waitForProcess(processName, timeoutSeconds)
  set startedAt to current date

  repeat
    tell application "System Events"
      if exists process processName then return
    end tell

    if (current date) - startedAt > timeoutSeconds then
      error "Timed out waiting for process: " & processName
    end if

    delay 0.1
  end repeat
end waitForProcess

on setChromeWindowMode(chromeAppName, processName, windowIndex, modeName)
  if windowIndex is missing value then return false

  try
    using terms from application "Google Chrome"
      tell application chromeAppName
        activate
        set index of window windowIndex to 1
        delay 0.08
        set mode of window 1 to modeName
      end tell
    end using terms from
    return true
  on error
    if modeName is "fullscreen" then
      tell application "System Events"
        tell process processName
          set frontmost to true
          keystroke "f" using {command down, control down}
        end tell
      end tell
      return true
    end if
  end try

  return false
end setChromeWindowMode

on clickNotesPlusViaJavascript(chromeAppName, notesWindowIndex, plusClicks)
  if plusClicks is less than or equal to 0 then return "skipped:steps"

  set jsSource to "(() => {" & return & ¬
    "  const steps = " & plusClicks & ";" & return & ¬
    "  const normalize = (v) => String(v || \"\").toLowerCase();" & return & ¬
    "  const visible = (el) => {" & return & ¬
    "    if (!el) return false;" & return & ¬
    "    const r = el.getBoundingClientRect();" & return & ¬
    "    return r.width > 0 && r.height > 0;" & return & ¬
    "  };" & return & ¬
    "  const scoreButton = (el) => {" & return & ¬
    "    const text = normalize(el.textContent).trim();" & return & ¬
    "    const aria = normalize(el.getAttribute(\"aria-label\"));" & return & ¬
    "    const title = normalize(el.getAttribute(\"title\"));" & return & ¬
    "    const blob = text + \" \" + aria + \" \" + title;" & return & ¬
    "    let score = 0;" & return & ¬
    "    if (text === \"+\") score += 6;" & return & ¬
    "    if (blob.includes(\"plus\")) score += 5;" & return & ¬
    "    if (blob.includes(\"increase\")) score += 4;" & return & ¬
    "    if (blob.includes(\"font\")) score += 4;" & return & ¬
    "    if (blob.includes(\"zoom\")) score += 3;" & return & ¬
    "    if (blob.includes(\"text\")) score += 2;" & return & ¬
    "    const r = el.getBoundingClientRect();" & return & ¬
    "    if (r.left > window.innerWidth * 0.55) score += 2;" & return & ¬
    "    if (r.top < window.innerHeight * 0.4) score += 2;" & return & ¬
    "    return score;" & return & ¬
    "  };" & return & ¬
    "  const candidates = Array.from(document.querySelectorAll(\"button,[role=\\\"button\\\"]\")).filter(visible);" & return & ¬
    "  if (!candidates.length) return \"not-found:no-visible-buttons\";" & return & ¬
    "  const ranked = candidates" & return & ¬
    "    .map((el) => ({el, score: scoreButton(el)}))" & return & ¬
    "    .filter((entry) => entry.score > 0)" & return & ¬
    "    .sort((a, b) => b.score - a.score);" & return & ¬
    "  if (!ranked.length) return \"not-found:no-plus-candidate\";" & return & ¬
    "  const target = ranked[0].el;" & return & ¬
    "  const rect = target.getBoundingClientRect();" & return & ¬
    "  target.scrollIntoView({block:\"nearest\", inline:\"nearest\"});" & return & ¬
    "  target.focus();" & return & ¬
    "  for (let i = 0; i < steps; i += 1) target.click();" & return & ¬
    "  return \"clicked:\" + steps + \":x=\" + Math.round(rect.left) + \":y=\" + Math.round(rect.top) + \":source=js\";" & return & ¬
    "})();"

  try
    using terms from application "Google Chrome"
      tell application chromeAppName
        set jsResult to execute active tab of window notesWindowIndex javascript jsSource
      end tell
    end using terms from
    if jsResult is missing value then return "not-found:missing-result"
    return jsResult as text
  on error errMsg number errNum
    return "error " & errNum & ": " & errMsg
  end try
end clickNotesPlusViaJavascript

on clickNotesPlusByBounds(processName, boundValues, plusClicks, clickDelaySeconds, rightOffset, topOffset, sourceLabel)
  if plusClicks is less than or equal to 0 then return "skipped:steps"

  set leftEdge to item 1 of boundValues
  set topEdge to item 2 of boundValues
  set rightEdge to item 3 of boundValues

  set clickX to rightEdge - rightOffset
  set clickY to topEdge + topOffset
  set clickXInt to clickX as integer
  set clickYInt to clickY as integer

  tell application "System Events"
    tell process processName
      set frontmost to true
      repeat plusClicks times
        click at {clickXInt, clickYInt}
        delay clickDelaySeconds
      end repeat
    end tell
  end tell

  return "clicked:" & plusClicks & ":x=" & clickXInt & ":y=" & clickYInt & ":source=" & sourceLabel
end clickNotesPlusByBounds

on clickNotesPlusByWindowBounds(chromeAppName, processName, notesWindowIndex, plusClicks, clickDelaySeconds, rightOffset, topOffset)
  if notesWindowIndex is missing value then return "error:missing-notes-window-index"

  try
    using terms from application "Google Chrome"
      tell application chromeAppName
        set notesWindowBounds to bounds of window notesWindowIndex
      end tell
    end using terms from
  on error errMsg number errNum
    return "error " & errNum & ": " & errMsg
  end try

  return my clickNotesPlusByBounds(processName, notesWindowBounds, plusClicks, clickDelaySeconds, rightOffset, topOffset, "window")
end clickNotesPlusByWindowBounds

set chromeApp to system attribute "CHROME_APP"
set primaryBoundsCSV to system attribute "PRIMARY_BOUNDS"
set notesBoundsCSV to system attribute "NOTES_BOUNDS"
set fullscreenPrimary to system attribute "FULLSCREEN_PRIMARY"
set fullscreenNotes to system attribute "FULLSCREEN_NOTES"
set launchDelayRaw to system attribute "LAUNCH_DELAY_SECONDS"
set presenterReadyDelayRaw to system attribute "PRESENTER_READY_DELAY_SECONDS"
set notesShortcutRetryIntervalRaw to system attribute "NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS"
set notesShortcutMaxWaitRaw to system attribute "NOTES_SHORTCUT_MAX_WAIT_SECONDS"
set notesPlusClickStepsRaw to system attribute "NOTES_PLUS_CLICK_STEPS"
set notesPlusMethodRaw to system attribute "NOTES_PLUS_METHOD"
set notesPlusReadyDelayRaw to system attribute "NOTES_PLUS_READY_DELAY_SECONDS"
set notesPlusClickDelayRaw to system attribute "NOTES_PLUS_CLICK_DELAY_SECONDS"
set notesPlusButtonRightOffsetRaw to system attribute "NOTES_PLUS_BUTTON_RIGHT_OFFSET"
set notesPlusButtonTopOffsetRaw to system attribute "NOTES_PLUS_BUTTON_TOP_OFFSET"
set launchFromEditMode to system attribute "LAUNCH_FROM_EDIT_MODE"
set expectNotesWindow to system attribute "EXPECT_NOTES_WINDOW"
set notesViaShortcut to system attribute "USE_PRESENTER_NOTES_SHORTCUT"
set timeoutRaw to system attribute "WINDOW_WAIT_TIMEOUT_SECONDS"

set launchDelay to launchDelayRaw as number
set presenterReadyDelay to presenterReadyDelayRaw as number
set notesShortcutRetryInterval to notesShortcutRetryIntervalRaw as number
set notesShortcutMaxWait to notesShortcutMaxWaitRaw as number
set notesPlusClickSteps to notesPlusClickStepsRaw as integer
set notesPlusReadyDelay to notesPlusReadyDelayRaw as number
set notesPlusClickDelay to notesPlusClickDelayRaw as number
set notesPlusButtonRightOffset to notesPlusButtonRightOffsetRaw as integer
set notesPlusButtonTopOffset to notesPlusButtonTopOffsetRaw as integer
set waitTimeout to timeoutRaw as number

set notesPlusMethod to notesPlusMethodRaw as text
if notesPlusMethod is not "auto" and notesPlusMethod is not "js" and notesPlusMethod is not "coords" then
  set notesPlusMethod to "auto"
end if

set primaryBounds to csvToBounds(primaryBoundsCSV)
set notesBounds to csvToBounds(notesBoundsCSV)

set notesMethodUsed to "skipped"
set notesFallbackReason to ""
set notesClickDetail to ""
set notesWindowFound to false
set notesWindowWaitResult to "not-requested"

if notesShortcutMaxWait < presenterReadyDelay then
  set notesShortcutMaxWait to presenterReadyDelay
end if

if notesShortcutMaxWait < notesShortcutRetryInterval then
  set notesShortcutMaxWait to notesShortcutRetryInterval
end if

my waitForProcess(chromeApp, waitTimeout)
my waitForWindowCount(chromeApp, 1, waitTimeout)

my waitForProcess(chromeApp, waitTimeout)
tell application "System Events"
  tell process chromeApp
    set frontmost to true
    set slidesWindow to window 1
    my clickWindowCenter(chromeApp, slidesWindow)

    if launchFromEditMode is "1" then
      keystroke return using {command down}
      delay launchDelay
      my clickWindowCenter(chromeApp, slidesWindow)
    end if

    if notesViaShortcut is "1" then
      set shortcutOpened to my triggerNotesShortcutWithRetries(chromeApp, chromeApp, notesShortcutMaxWait, notesShortcutRetryInterval)
      if shortcutOpened then
        set notesWindowWaitResult to "shortcut-opened"
      else
        set notesWindowWaitResult to "shortcut-timeout"
      end if
      delay launchDelay
    end if
  end tell
end tell

if expectNotesWindow is "1" then
  set notesWindowFound to my waitForNotesChromeWindow(chromeApp, waitTimeout)
  if notesWindowFound then
    if notesWindowWaitResult is "not-requested" then
      set notesWindowWaitResult to "wait-opened"
    else if notesWindowWaitResult is "shortcut-opened" then
      set notesWindowWaitResult to notesWindowWaitResult & "|confirmed"
    end if
  else
    if notesWindowWaitResult is "not-requested" then
      set notesWindowWaitResult to "wait-timeout"
    else
      set notesWindowWaitResult to notesWindowWaitResult & "|wait-timeout"
    end if
  end if
else
  set notesWindowFound to my hasNotesChromeWindow(chromeApp)
end if

set slidesChromeIndex to missing value
set notesChromeIndex to missing value

using terms from application "Google Chrome"
  tell application chromeApp
    set chromeWindowCount to count of windows

    repeat with i from 1 to chromeWindowCount
      set oneTitle to ""
      set oneURL to ""

      try
        set oneTitle to title of active tab of window i
      end try

      try
        set oneURL to URL of active tab of window i
      end try

      if notesChromeIndex is missing value and my isNotesChromeWindow(oneTitle, oneURL) then
        set notesChromeIndex to i
      end if

      if slidesChromeIndex is missing value and oneURL contains "/presentation/d/" and oneURL contains "/present" then
        set slidesChromeIndex to i
      end if
    end repeat

    if slidesChromeIndex is missing value and chromeWindowCount is greater than 0 then
      set slidesChromeIndex to 1
    end if

    if notesChromeIndex is not missing value and notesChromeIndex is slidesChromeIndex then
      set notesChromeIndex to missing value
    end if
  end tell
end using terms from

my waitForProcess(chromeApp, waitTimeout)

if slidesChromeIndex is not missing value then
  using terms from application "Google Chrome"
    tell application chromeApp
      set bounds of window slidesChromeIndex to primaryBounds
    end tell
  end using terms from
end if

if notesChromeIndex is not missing value then
  using terms from application "Google Chrome"
    tell application chromeApp
      set bounds of window notesChromeIndex to notesBounds
      try
        set mode of window notesChromeIndex to "normal"
      end try
    end tell
  end using terms from
end if

if fullscreenPrimary is "1" and slidesChromeIndex is not missing value then
  my setChromeWindowMode(chromeApp, chromeApp, slidesChromeIndex, "fullscreen")
  delay launchDelay
end if

if notesChromeIndex is not missing value then
  delay notesPlusReadyDelay

  if notesPlusClickSteps > 0 then
    set notesMethodUsed to "failed"

    if notesPlusMethod is "auto" or notesPlusMethod is "js" then
      set jsResult to my clickNotesPlusViaJavascript(chromeApp, notesChromeIndex, notesPlusClickSteps)
      if my startsWith(jsResult, "clicked:") then
        set notesMethodUsed to "js"
        set notesClickDetail to jsResult
      else
        set notesFallbackReason to jsResult
      end if
    end if

    if notesMethodUsed is "failed" and (notesPlusMethod is "auto" or notesPlusMethod is "coords") then
      set coordResult to my clickNotesPlusByWindowBounds(chromeApp, chromeApp, notesChromeIndex, notesPlusClickSteps, notesPlusClickDelay, notesPlusButtonRightOffset, notesPlusButtonTopOffset)
      if my startsWith(coordResult, "clicked:") then
        set notesMethodUsed to "coords"
        set notesClickDetail to coordResult
      else
        if notesFallbackReason is "" then
          set notesFallbackReason to coordResult
        else
          set notesFallbackReason to notesFallbackReason & " | " & coordResult
        end if

        set coordBoundsResult to my clickNotesPlusByBounds(chromeApp, notesBounds, notesPlusClickSteps, notesPlusClickDelay, notesPlusButtonRightOffset, notesPlusButtonTopOffset, "config")
        if my startsWith(coordBoundsResult, "clicked:") then
          set notesMethodUsed to "coords"
          set notesClickDetail to coordBoundsResult
        else
          if notesFallbackReason is "" then
            set notesFallbackReason to coordBoundsResult
          else
            set notesFallbackReason to notesFallbackReason & " | " & coordBoundsResult
          end if
        end if
      end if
    end if
  else
    set notesMethodUsed to "skipped"
  end if

  if fullscreenNotes is "1" then
    my setChromeWindowMode(chromeApp, chromeApp, notesChromeIndex, "fullscreen")
    delay launchDelay
  end if
end if

if expectNotesWindow is "1" and notesChromeIndex is missing value then
  if notesFallbackReason is "" then
    set notesFallbackReason to "notes-window-not-found"
  else
    set notesFallbackReason to notesFallbackReason & " | notes-window-not-found"
  end if
end if

return "NOTES_METHOD_CONFIG=" & notesPlusMethod & linefeed & "NOTES_METHOD_USED=" & notesMethodUsed & linefeed & "NOTES_CLICK_DETAIL=" & notesClickDetail & linefeed & "NOTES_WINDOW_EXPECTED=" & expectNotesWindow & linefeed & "NOTES_WINDOW_FOUND=" & notesWindowFound & linefeed & "NOTES_WINDOW_WAIT_RESULT=" & notesWindowWaitResult & linefeed & "NOTES_SHORTCUT_WAIT_SECONDS=" & notesShortcutMaxWait & linefeed & "NOTES_FALLBACK_REASON=" & notesFallbackReason
APPLESCRIPT
)"

while IFS= read -r summary_line; do
  if [[ -n "$summary_line" ]]; then
    echo "[slides_machine_runner] $summary_line"
  fi
done <<< "$apple_summary"
