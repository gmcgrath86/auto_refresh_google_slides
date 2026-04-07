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
  CHROME_FORCE_RENDERER_ACCESSIBILITY=1
  CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY=1
  BOUNDS_MODE="auto"
  DISPLAY_ASSIGNMENT="slides:extended,notes:desktop"
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
  NOTES_PLUS_CLICK_STEPS=7
  NOTES_PLUS_METHOD="auto"   # auto/js/coords/ax
  NOTES_PLUS_READY_DELAY_SECONDS=0.45
  NOTES_PLUS_CLICK_DELAY_SECONDS=0.08
  NOTES_PLUS_BUTTON_RIGHT_OFFSET=56
  NOTES_PLUS_BUTTON_TOP_OFFSET=164
  OPEN_RETRY_COUNT=3
  OPEN_RETRY_DELAY_SECONDS=1.0
  WINDOW_WAIT_TIMEOUT_SECONDS=20
  RESTORE_PREVIOUS_SLIDE_ON_REFRESH=1
  RESTORE_SLIDE_CAPTURE_RETRY_COUNT=8
  RESTORE_SLIDE_CAPTURE_RETRY_DELAY_SECONDS=0.35
  RESTORE_SLIDE_JUMP_RETRY_COUNT=3
  RESTORE_SLIDE_JUMP_RETRY_DELAY_SECONDS=0.4
  RESTORE_SLIDE_VERIFY_RETRY_COUNT=12
  RESTORE_SLIDE_VERIFY_RETRY_DELAY_SECONDS=0.4
  RESTORE_SLIDE_REQUIRE_CAPTURE_WHEN_PRESENTING=1
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
CHROME_FORCE_RENDERER_ACCESSIBILITY="${CHROME_FORCE_RENDERER_ACCESSIBILITY:-1}"
CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY="${CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY:-1}"
BOUNDS_MODE="${BOUNDS_MODE:-auto}"
DISPLAY_ASSIGNMENT="${DISPLAY_ASSIGNMENT:-slides:extended,notes:desktop}"
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
NOTES_PLUS_CLICK_STEPS="${NOTES_PLUS_CLICK_STEPS:-${NOTES_ZOOM_STEPS:-7}}"
NOTES_PLUS_METHOD="${NOTES_PLUS_METHOD:-auto}"
NOTES_PLUS_READY_DELAY_SECONDS="${NOTES_PLUS_READY_DELAY_SECONDS:-0.45}"
NOTES_PLUS_CLICK_DELAY_SECONDS="${NOTES_PLUS_CLICK_DELAY_SECONDS:-${NOTES_ZOOM_STEP_DELAY_SECONDS:-0.08}}"
NOTES_PLUS_BUTTON_RIGHT_OFFSET="${NOTES_PLUS_BUTTON_RIGHT_OFFSET:-56}"
NOTES_PLUS_BUTTON_TOP_OFFSET="${NOTES_PLUS_BUTTON_TOP_OFFSET:-164}"
OPEN_RETRY_COUNT="${OPEN_RETRY_COUNT:-3}"
OPEN_RETRY_DELAY_SECONDS="${OPEN_RETRY_DELAY_SECONDS:-1.0}"
WINDOW_WAIT_TIMEOUT_SECONDS="${WINDOW_WAIT_TIMEOUT_SECONDS:-20}"
NOTES_SHORTCUT_MAX_WAIT_SECONDS="${NOTES_SHORTCUT_MAX_WAIT_SECONDS:-$WINDOW_WAIT_TIMEOUT_SECONDS}"
RESTORE_PREVIOUS_SLIDE_ON_REFRESH="${RESTORE_PREVIOUS_SLIDE_ON_REFRESH:-1}"
RESTORE_SLIDE_CAPTURE_RETRY_COUNT="${RESTORE_SLIDE_CAPTURE_RETRY_COUNT:-8}"
RESTORE_SLIDE_CAPTURE_RETRY_DELAY_SECONDS="${RESTORE_SLIDE_CAPTURE_RETRY_DELAY_SECONDS:-0.35}"
RESTORE_SLIDE_JUMP_RETRY_COUNT="${RESTORE_SLIDE_JUMP_RETRY_COUNT:-3}"
RESTORE_SLIDE_JUMP_RETRY_DELAY_SECONDS="${RESTORE_SLIDE_JUMP_RETRY_DELAY_SECONDS:-0.4}"
RESTORE_SLIDE_VERIFY_RETRY_COUNT="${RESTORE_SLIDE_VERIFY_RETRY_COUNT:-12}"
RESTORE_SLIDE_VERIFY_RETRY_DELAY_SECONDS="${RESTORE_SLIDE_VERIFY_RETRY_DELAY_SECONDS:-0.4}"
RESTORE_SLIDE_REQUIRE_CAPTURE_WHEN_PRESENTING="${RESTORE_SLIDE_REQUIRE_CAPTURE_WHEN_PRESENTING:-1}"

# Prefer AXPress over coordinate clicking when auto mode is selected.
if [[ "$NOTES_PLUS_METHOD" == "auto" && "$CHROME_FORCE_RENDERER_ACCESSIBILITY" == "1" ]]; then
  if [[ "$NOTES_PLUS_CLICK_STEPS" =~ ^[0-9]+$ ]] && (( NOTES_PLUS_CLICK_STEPS > 0 )); then
    NOTES_PLUS_METHOD="ax"
  fi
fi

SLIDES_PRESENT_URL="${SLIDES_PRESENT_URL:-}"
SLIDES_NOTES_URL="${SLIDES_NOTES_URL:-}"
SLIDES_SOURCE_URL="${SLIDES_SOURCE_URL:-}"
SLIDES_LAUNCH_URL=""
SOURCE_DECK_ID=""
DISPLAY_COUNT=""
BOUNDS_SOURCE=""
RESTORE_PRESENT_URL=""
RESTORE_PRESENT_SLIDE_ID=""
RESTORE_SLIDE_NUMBER=""
RESTORE_SLIDE_RESULT="skipped"
RESTORE_SLIDE_CAPTURE_RESULT="not-attempted"
RESTORE_SLIDE_PRESENTATION_OPEN="unknown"
RESTORE_PRESENT_SLIDE_ID_STRICT_VERIFY=0
LAST_CAPTURE_LIVE_SLIDE_RESULT=""
LAST_PRESENTER_WINDOW_CHECK_RESULT=""

if [[ "$BOUNDS_MODE" != "auto" && "$BOUNDS_MODE" != "manual" ]]; then
  echo "Invalid BOUNDS_MODE=$BOUNDS_MODE (expected auto or manual)" >&2
  exit 1
fi

if [[ "$NOTES_PLUS_METHOD" != "auto" && "$NOTES_PLUS_METHOD" != "js" && "$NOTES_PLUS_METHOD" != "coords" && "$NOTES_PLUS_METHOD" != "ax" ]]; then
  echo "Invalid NOTES_PLUS_METHOD=$NOTES_PLUS_METHOD (expected auto, js, coords, or ax)" >&2
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

extract_slide_param_from_url() {
  local input_url="$1"

  if [[ "$input_url" =~ (^|[?&])slide=([^&#]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

is_audience_present_url() {
  local input_url="$1"

  [[ "$input_url" =~ ^https?:// ]] || return 1
  [[ "$input_url" =~ /presentation/d/[^/?#]+/present([/?#]|$) ]] || return 1
  [[ "$input_url" != *"presenter=true"* ]] || return 1
  [[ "$input_url" != *"/presenter"* ]] || return 1
}

capture_live_present_url() {
  local present_url=""

  present_url="$(
    CHROME_APP_RUNTIME="$CHROME_APP" /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
set chromeApp to system attribute "CHROME_APP_RUNTIME"

using terms from application "Google Chrome"
  tell application chromeApp
    set windowCount to count of windows

    repeat with i from 1 to windowCount
      set oneTitle to ""
      set oneURL to ""

      try
        set oneTitle to title of active tab of window i
      end try

      try
        set oneURL to URL of active tab of window i
      end try

      if oneURL contains "/presentation/d/" and (oneURL contains "/present?" or oneURL contains "/present#" or oneURL contains "/present/" or oneURL ends with "/present") and oneURL does not contain "presenter=true" and oneURL does not contain "/presenter" and oneTitle does not contain "Presenter view" then
        return oneURL
      end if
    end repeat

    repeat with i from 1 to windowCount
      set oneURL to ""
      try
        set oneURL to URL of active tab of window i
      end try

      if oneURL contains "/presentation/d/" and (oneURL contains "/present?" or oneURL contains "/present#" or oneURL contains "/present/" or oneURL ends with "/present") and oneURL does not contain "presenter=true" and oneURL does not contain "/presenter" then
        return oneURL
      end if
    end repeat
  end tell
end using terms from
APPLESCRIPT
  )"

  present_url="$(printf '%s' "$present_url" | tr -d '\r\n')"

  if is_audience_present_url "$present_url"; then
    printf '%s\n' "$present_url"
    return 0
  fi

  return 1
}

wait_for_live_present_url() {
  local max_wait_seconds="${1:-6}"
  local started_at
  local present_url=""

  started_at="$(date +%s)"
  while true; do
    present_url="$(capture_live_present_url || true)"
    if [[ -n "$present_url" ]]; then
      printf '%s\n' "$present_url"
      return 0
    fi

    if (( "$(date +%s)" - started_at >= max_wait_seconds )); then
      return 1
    fi

    sleep 0.25
  done
}

verify_live_present_slide_id() {
  local expected_slide_id="$1"
  local current_present_url=""
  local current_slide_id=""

  if [[ -z "$expected_slide_id" ]]; then
    printf 'error:missing-slide-id\n'
    return 1
  fi

  current_present_url="$(capture_live_present_url || true)"
  if [[ -z "$current_present_url" ]]; then
    printf 'error:present-url-not-found\n'
    return 1
  fi

  current_slide_id="$(extract_slide_param_from_url "$current_present_url" || true)"
  if [[ "$current_slide_id" == "$expected_slide_id" ]]; then
    printf 'verified-url:%s\n' "$expected_slide_id"
    return 0
  fi

  if [[ -n "$current_slide_id" ]]; then
    printf 'error:present-url-mismatch:expected=%s:actual=%s\n' "$expected_slide_id" "$current_slide_id"
  else
    printf 'error:present-url-missing-slide-param\n'
  fi

  return 1
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
  var slides = "extended"
  var notes = "desktop"

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

func boundsEqual(_ a: Bounds, _ b: Bounds) -> Bool {
  return a.left == b.left &&
    a.top == b.top &&
    a.right == b.right &&
    a.bottom == b.bottom
}

func pickScreen(named token: String, screens: [Bounds], main: Bounds) -> Bounds {
  if screens.isEmpty { return main }
  let lowered = token.lowercased()
  switch lowered {
  case "desktop", "mirrored", "mirror", "primary", "main", "notes":
    return main
  case "extended", "secondary", "nonmain", "external", "slides":
    let nonMainScreens = screens.filter { !boundsEqual($0, main) }
    if nonMainScreens.isEmpty { return main }
    if nonMainScreens.count == 1 { return nonMainScreens[0] }
    return nonMainScreens.max(by: { lhs, rhs in
      let lhsArea = lhs.width * lhs.height
      let rhsArea = rhs.width * rhs.height
      if lhsArea == rhsArea {
        return centerDistanceSquared(lhs, main) < centerDistanceSquared(rhs, main)
      }
      return lhsArea < rhsArea
    }) ?? nonMainScreens[0]
  case "leftmost":
    return screens.min(by: { $0.left < $1.left }) ?? main
  case "rightmost":
    return screens.max(by: { $0.left < $1.left }) ?? main
  default:
    return main
  }
}

let env = ProcessInfo.processInfo.environment
let modeRaw = (env["BOUNDS_MODE_RUNTIME"] ?? "auto").lowercased()
let mode = (modeRaw == "manual") ? "manual" : "auto"
let assignment = env["DISPLAY_ASSIGNMENT_RUNTIME"] ?? "slides:extended,notes:desktop"
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

if [[ "$RESTORE_PREVIOUS_SLIDE_ON_REFRESH" == "1" ]]; then
  RESTORE_PRESENT_URL="$(capture_live_present_url || true)"
  if [[ -n "$RESTORE_PRESENT_URL" ]]; then
    RESTORE_SLIDE_PRESENTATION_OPEN="yes"
    SLIDES_PRESENT_URL="$RESTORE_PRESENT_URL"
    SLIDES_SOURCE_URL="$(derive_source_url "$RESTORE_PRESENT_URL" || true)"

    RESTORE_PRESENT_SLIDE_ID="$(extract_slide_param_from_url "$RESTORE_PRESENT_URL" || true)"
    if [[ -n "$RESTORE_PRESENT_SLIDE_ID" ]]; then
      RESTORE_SLIDE_CAPTURE_RESULT="captured-url:${RESTORE_PRESENT_SLIDE_ID}"
    else
      RESTORE_SLIDE_CAPTURE_RESULT="captured-url:missing-slide-param"
    fi
  fi
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

echo "[slides_machine_runner] source url=$SLIDES_SOURCE_URL"
echo "[slides_machine_runner] present url=$SLIDES_PRESENT_URL"
echo "[slides_machine_runner] launch url=$SLIDES_LAUNCH_URL"

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
    set openInNewWindow to false
    if targetUrl contains "/presentation/d/" and (targetUrl contains "/present?" or targetUrl contains "/present#" or targetUrl contains "/present/" or targetUrl ends with "/present") and targetUrl does not contain "/presenter" and targetUrl does not contain "presenter=true" then
      set openInNewWindow to true
    end if

    if openInNewWindow then
      set newWindow to make new window
      set URL of active tab of newWindow to targetUrl
      set index of newWindow to 1
    else if (count of windows) is greater than 0 then
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

chrome_process_has_force_renderer_accessibility() {
  local chrome_pid
  local chrome_cmd

  chrome_pid="$(pgrep -x "$CHROME_APP" | head -n 1 || true)"
  if [[ -z "$chrome_pid" ]]; then
    return 1
  fi

  chrome_cmd="$(ps -p "$chrome_pid" -o command= 2>/dev/null || true)"
  [[ "$chrome_cmd" == *"--force-renderer-accessibility"* ]]
}

should_require_renderer_accessibility() {
  if [[ "$CHROME_FORCE_RENDERER_ACCESSIBILITY" != "1" ]]; then
    return 1
  fi

  if [[ ! "$NOTES_PLUS_CLICK_STEPS" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( NOTES_PLUS_CLICK_STEPS <= 0 )); then
    return 1
  fi

  [[ "$NOTES_PLUS_METHOD" == "auto" || "$NOTES_PLUS_METHOD" == "ax" ]]
}

ensure_chrome_force_renderer_accessibility() {
  if ! should_require_renderer_accessibility; then
    return 0
  fi

  if pgrep -x "$CHROME_APP" >/dev/null 2>&1; then
    if chrome_process_has_force_renderer_accessibility; then
      return 0
    fi

    if [[ "$CHROME_RESTART_FOR_RENDERER_ACCESSIBILITY" != "1" ]]; then
      echo "[slides_machine_runner] WARN: Chrome is running without --force-renderer-accessibility; notes AX zoom may fail."
      return 0
    fi

    pkill -x "$CHROME_APP" >/dev/null 2>&1 || true
    sleep 0.8
  fi

  open -a "$CHROME_APP" --args --force-renderer-accessibility >/dev/null 2>&1 || true
  if ! wait_for_chrome_process 8; then
    echo "[slides_machine_runner] WARN: Unable to launch Chrome with --force-renderer-accessibility."
    return 0
  fi

  sleep 0.5
  return 0
}

resolve_hs_binary() {
  local hs_bin=""

  if command -v hs >/dev/null 2>&1; then
    hs_bin="$(command -v hs)"
  elif [[ -x "/opt/homebrew/bin/hs" ]]; then
    hs_bin="/opt/homebrew/bin/hs"
  elif [[ -x "/usr/local/bin/hs" ]]; then
    hs_bin="/usr/local/bin/hs"
  fi

  printf '%s\n' "$hs_bin"
}

ocr_text_from_image() {
  local image_path="$1"

  swift - "$image_path" <<'SWIFT' 2>/dev/null || true
import AppKit
import Foundation
import Vision

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path) else {
  exit(1)
}

var rect = CGRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
  exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .fast
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])

for observation in request.results ?? [] {
  if let candidate = observation.topCandidates(1).first {
    print(candidate.string)
  }
}
SWIFT
}

extract_slide_number_from_text() {
  local input_text="$1"

  if [[ "$input_text" =~ [Ss]lide[[:space:]]+([0-9]+)[[:space:]]+of[[:space:]]+[0-9]+ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$input_text" =~ [Ss]lide[[:space:]]+([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

capture_slide_number_from_bounds_via_ocr() {
  local bounds_csv="$1"
  local capture_height="$2"
  local label="$3"
  local left=""
  local top=""
  local right=""
  local bottom=""
  local width=""
  local height=""
  local screenshot_path=""
  local ocr_text=""
  local slide_number=""

  IFS=',' read -r left top right bottom <<< "$bounds_csv"
  if [[ -z "$left" || -z "$top" || -z "$right" || -z "$bottom" ]]; then
    LAST_CAPTURE_LIVE_SLIDE_RESULT="error:ocr-invalid-bounds:${label}"
    return 1
  fi

  width=$(( right - left ))
  height=$(( bottom - top ))
  if (( width <= 0 || height <= 0 )); then
    LAST_CAPTURE_LIVE_SLIDE_RESULT="error:ocr-empty-bounds:${label}"
    return 1
  fi

  if (( capture_height > height )); then
    capture_height="$height"
  fi

  screenshot_path="$(mktemp "/tmp/slides-ocr-${label}.XXXXXX.png")"
  if ! screencapture -x -R"${left},${top},${width},${capture_height}" "$screenshot_path" >/dev/null 2>&1; then
    rm -f "$screenshot_path"
    LAST_CAPTURE_LIVE_SLIDE_RESULT="error:ocr-screencapture-failed:${label}"
    return 1
  fi

  ocr_text="$(ocr_text_from_image "$screenshot_path")"
  rm -f "$screenshot_path"

  slide_number="$(extract_slide_number_from_text "$ocr_text" || true)"
  if [[ "$slide_number" =~ ^[0-9]+$ ]] && (( slide_number > 0 )); then
    LAST_CAPTURE_LIVE_SLIDE_RESULT="ocr:${label}:${slide_number}"
    printf '%s\n' "$slide_number"
    return 0
  fi

  LAST_CAPTURE_LIVE_SLIDE_RESULT="error:ocr-slide-number-not-found:${label}"
  return 1
}

capture_live_slide_number_via_screen_ocr() {
  local slide_number=""

  if [[ -n "${NOTES_BOUNDS:-}" ]]; then
    if slide_number="$(capture_slide_number_from_bounds_via_ocr "$NOTES_BOUNDS" 240 "notes")"; then
      printf '%s\n' "$slide_number"
      return 0
    fi
  fi

  if [[ -n "${PRIMARY_BOUNDS:-}" ]]; then
    if slide_number="$(capture_slide_number_from_bounds_via_ocr "$PRIMARY_BOUNDS" 220 "slides")"; then
      printf '%s\n' "$slide_number"
      return 0
    fi
  fi

  return 1
}

capture_live_slide_number_via_hammerspoon_raw() {
  local hs_bin=""
  local hs_result=""
  local chrome_app_lua
  local hs_script

  hs_bin="$(resolve_hs_binary)"
  if [[ -z "$hs_bin" ]]; then
    printf 'error:hs-not-found\n'
    return 1
  fi

  chrome_app_lua="$(printf '%s' "$CHROME_APP" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  hs_script="$(cat <<LUA
local ax = require("hs.axuielement")
local appName = "${chrome_app_lua}"

local app = hs.application.get(appName)
if not app then
  print("error:chrome-not-running")
  return
end

local targetWindow = nil
for _, oneWindow in ipairs(app:allWindows()) do
  local title = oneWindow:title() or ""
  if title:find("Presenter view", 1, true) then
    if oneWindow:isFullScreen() then
      targetWindow = oneWindow
      break
    end
    if not targetWindow then
      targetWindow = oneWindow
    end
  end
end

if not targetWindow then
  print("error:presenter-window-not-found")
  return
end

local root = ax.windowElement(targetWindow)
if not root then
  print("error:presenter-ax-root-not-found")
  return
end

local queue = {root}
local safetyCounter = 0

while #queue > 0 and safetyCounter < 5000 do
  safetyCounter = safetyCounter + 1
  local element = table.remove(queue, 1)
  for _, attributeName in ipairs({"AXTitle", "AXDescription", "AXValue"}) do
    local rawValue = element:attributeValue(attributeName)
    local text = tostring(rawValue or "")
    local slideNumber = text:match("[Ss]lide%s+(%d+)%s+of%s+%d+")
    if slideNumber then
      print(slideNumber)
      return
    end
  end

  local children = element:attributeValue("AXChildren")
  if type(children) == "table" then
    for _, child in ipairs(children) do
      if type(child) == "userdata" then
        table.insert(queue, child)
      end
    end
  end
end

print("error:slide-number-not-found")
LUA
)"

  hs_result="$("$hs_bin" -c "$hs_script" 2>/dev/null || true)"
  hs_result="$(printf '%s' "$hs_result" | tr -d '\r' | tail -n 1)"

  if [[ -z "$hs_result" ]]; then
    hs_result="error:empty-slide-capture-result"
  fi

  printf '%s\n' "$hs_result"
}

capture_live_slide_number_via_hammerspoon() {
  local hs_result=""

  hs_result="$(capture_live_slide_number_via_hammerspoon_raw || true)"
  hs_result="$(printf '%s' "$hs_result" | tr -d '\r' | tail -n 1)"
  LAST_CAPTURE_LIVE_SLIDE_RESULT="$hs_result"

  if [[ "$hs_result" =~ ^[0-9]+$ ]] && (( hs_result > 0 )); then
    printf '%s\n' "$hs_result"
    return 0
  fi

  return 1
}

has_live_presentation_window_via_hammerspoon() {
  local hs_bin=""
  local hs_result=""
  local chrome_app_lua
  local hs_script

  hs_bin="$(resolve_hs_binary)"
  if [[ -z "$hs_bin" ]]; then
    LAST_PRESENTER_WINDOW_CHECK_RESULT="error:hs-not-found"
    return 1
  fi

  chrome_app_lua="$(printf '%s' "$CHROME_APP" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  hs_script="$(cat <<LUA
local appName = "${chrome_app_lua}"

local app = hs.application.get(appName)
if not app then
  print("absent")
  return
end

for _, oneWindow in ipairs(app:allWindows()) do
  local title = oneWindow:title() or ""
  if title:find("Presenter view", 1, true) then
    print("present")
    return
  end
end

print("absent")
LUA
)"

  hs_result="$("$hs_bin" -c "$hs_script" 2>/dev/null || true)"
  hs_result="$(printf '%s' "$hs_result" | tr -d '\r' | tail -n 1)"

  if [[ -z "$hs_result" ]]; then
    hs_result="error:empty-presenter-window-check-result"
  fi

  LAST_PRESENTER_WINDOW_CHECK_RESULT="$hs_result"
  [[ "$hs_result" == "present" ]]
}

capture_live_slide_number_with_retries() {
  local attempt=""
  local captured_slide=""
  local last_result="error:slide-capture-not-attempted"

  for (( attempt=1; attempt<=RESTORE_SLIDE_CAPTURE_RETRY_COUNT; attempt++ )); do
    if captured_slide="$(capture_live_slide_number_via_screen_ocr)"; then
      RESTORE_SLIDE_CAPTURE_RESULT="captured:${captured_slide}:source=ocr:attempt=${attempt}"
      printf '%s\n' "$captured_slide"
      return 0
    fi

    if captured_slide="$(capture_live_slide_number_via_hammerspoon)"; then
      RESTORE_SLIDE_CAPTURE_RESULT="captured:${captured_slide}:attempt=${attempt}"
      printf '%s\n' "$captured_slide"
      return 0
    fi

    last_result="${LAST_CAPTURE_LIVE_SLIDE_RESULT:-error:slide-capture-empty}:attempt=${attempt}"
    if (( attempt < RESTORE_SLIDE_CAPTURE_RETRY_COUNT )); then
      sleep "$RESTORE_SLIDE_CAPTURE_RETRY_DELAY_SECONDS"
    fi
  done

  RESTORE_SLIDE_CAPTURE_RESULT="$last_result"
  return 1
}

trigger_slide_jump_via_hammerspoon() {
  local slide_number="$1"
  local hs_bin=""
  local hs_result=""
  local chrome_app_lua
  local hs_script

  if [[ ! "$slide_number" =~ ^[0-9]+$ ]] || (( slide_number <= 0 )); then
    printf 'error:invalid-slide-number\n'
    return 1
  fi

  hs_bin="$(resolve_hs_binary)"
  if [[ -z "$hs_bin" ]]; then
    printf 'error:hs-not-found\n'
    return 1
  fi

  chrome_app_lua="$(printf '%s' "$CHROME_APP" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  hs_script="$(cat <<LUA
local appName = "${chrome_app_lua}"
local slideNumber = tonumber("${slide_number}") or 0

if slideNumber <= 0 then
  print("error:invalid-slide-number")
  return
end

local app = hs.application.get(appName)
if not app then
  print("error:chrome-not-running")
  return
end

local targetWindow = nil
local fallbackWindow = nil

for _, oneWindow in ipairs(app:allWindows()) do
  local title = oneWindow:title() or ""
  if oneWindow:isStandard() and title:find("Google Slides", 1, true) and not title:find("Presenter view", 1, true) then
    if oneWindow:isFullScreen() then
      targetWindow = oneWindow
      break
    end
    if not targetWindow then
      targetWindow = oneWindow
    end
  end

  if oneWindow:isStandard() and not fallbackWindow then
    fallbackWindow = oneWindow
  end
end

if not targetWindow then
  targetWindow = fallbackWindow
end

if not targetWindow then
  print("error:slides-window-not-found")
  return
end

app:activate(true)
targetWindow:focus()
hs.timer.usleep(180000)
hs.eventtap.keyStrokes(tostring(math.floor(slideNumber)))
hs.timer.usleep(70000)
hs.eventtap.keyStroke({}, "return")
print("jumped:" .. tostring(math.floor(slideNumber)))
LUA
)"

  hs_result="$("$hs_bin" -c "$hs_script" 2>/dev/null || true)"
  hs_result="$(printf '%s' "$hs_result" | tr -d '\r' | tail -n 1)"

  if [[ -z "$hs_result" ]]; then
    hs_result="error:empty-slide-restore-result"
  fi

  printf '%s\n' "$hs_result"
  [[ "$hs_result" == jumped:* ]]
}

verify_restored_slide_number() {
  local slide_number="$1"
  local attempt=""
  local current_slide=""
  local last_result="error:restore-verify-not-attempted"

  for (( attempt=1; attempt<=RESTORE_SLIDE_VERIFY_RETRY_COUNT; attempt++ )); do
    if current_slide="$(capture_live_slide_number_via_screen_ocr)"; then
      if [[ "$current_slide" == "$slide_number" ]]; then
        printf 'verified:%s:attempt=%s\n' "$slide_number" "$attempt"
        return 0
      fi

      last_result="error:restore-verify-mismatch:last-slide=${current_slide}:attempt=${attempt}"
    elif current_slide="$(capture_live_slide_number_via_hammerspoon)"; then
      if [[ "$current_slide" == "$slide_number" ]]; then
        printf 'verified:%s:attempt=%s\n' "$slide_number" "$attempt"
        return 0
      fi

      last_result="error:restore-verify-mismatch:last-slide=${current_slide}:attempt=${attempt}"
    else
      last_result="${LAST_CAPTURE_LIVE_SLIDE_RESULT:-error:restore-verify-empty}:attempt=${attempt}"
    fi

    if (( attempt < RESTORE_SLIDE_VERIFY_RETRY_COUNT )); then
      sleep "$RESTORE_SLIDE_VERIFY_RETRY_DELAY_SECONDS"
    fi
  done

  printf '%s\n' "$last_result"
  return 1
}

restore_slide_number_via_hammerspoon() {
  local slide_number="$1"
  local attempt=""
  local jump_result=""
  local verify_result=""
  local last_result="error:restore-not-attempted"

  if [[ ! "$slide_number" =~ ^[0-9]+$ ]] || (( slide_number <= 0 )); then
    printf 'error:invalid-slide-number\n'
    return 1
  fi

  for (( attempt=1; attempt<=RESTORE_SLIDE_JUMP_RETRY_COUNT; attempt++ )); do
    jump_result="$(trigger_slide_jump_via_hammerspoon "$slide_number" || true)"
    if [[ "$jump_result" != jumped:* ]]; then
      last_result="${jump_result:-error:empty-slide-restore-result}:attempt=${attempt}"
      if (( attempt < RESTORE_SLIDE_JUMP_RETRY_COUNT )); then
        sleep "$RESTORE_SLIDE_JUMP_RETRY_DELAY_SECONDS"
      fi
      continue
    fi

    if verify_result="$(verify_restored_slide_number "$slide_number")"; then
      printf '%s\n' "$verify_result"
      return 0
    fi

    last_result="${verify_result:-error:restore-verify-empty}:jump-attempt=${attempt}"
    if (( attempt < RESTORE_SLIDE_JUMP_RETRY_COUNT )); then
      sleep "$RESTORE_SLIDE_JUMP_RETRY_DELAY_SECONDS"
    fi
  done

  printf '%s\n' "$last_result"
  return 1
}

click_notes_plus_via_hammerspoon_axpress() {
  if [[ ! "$NOTES_PLUS_CLICK_STEPS" =~ ^[0-9]+$ ]] || (( NOTES_PLUS_CLICK_STEPS <= 0 )); then
    printf 'skipped:steps\n'
    return 0
  fi

  local hs_bin=""
  hs_bin="$(resolve_hs_binary)"

  if [[ -z "$hs_bin" ]]; then
    printf 'error:hs-not-found\n'
    return 1
  fi

  local hs_result
  local chrome_app_lua
  local hs_script
  chrome_app_lua="$(printf '%s' "$CHROME_APP" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  hs_script="$(cat <<LUA
local ax = require("hs.axuielement")
local appName = "${chrome_app_lua}"
local steps = tonumber("${NOTES_PLUS_CLICK_STEPS}") or 0
local clickDelaySeconds = tonumber("${NOTES_PLUS_CLICK_DELAY_SECONDS}") or 0.08

if steps <= 0 then
  print("skipped:steps")
  return
end

local app = hs.application.get(appName)
if not app then
  print("error:chrome-not-running")
  return
end

local targetWindow = nil
for _, oneWindow in ipairs(app:allWindows()) do
  local title = oneWindow:title() or ""
  if title:find("Presenter view", 1, true) then
    if oneWindow:isFullScreen() then
      targetWindow = oneWindow
      break
    end
    if not targetWindow then
      targetWindow = oneWindow
    end
  end
end

if not targetWindow then
  print("error:presenter-window-not-found")
  return
end

app:activate(true)
targetWindow:focus()
hs.timer.usleep(180000)

local root = ax.windowElement(targetWindow)

local queue = {}
local zoomInButton = nil
local speakerNotesTab = nil
local safetyCounter = 0
if root then
  table.insert(queue, root)
end

while #queue > 0 and safetyCounter < 4000 do
  safetyCounter = safetyCounter + 1
  local element = table.remove(queue, 1)
  local role = element:attributeValue("AXRole")

  if role == "AXButton" then
    local desc = tostring(element:attributeValue("AXDescription") or "")
    if desc == "Zoom in" then
      zoomInButton = element
    end
  elseif role == "AXRadioButton" then
    local title = tostring(element:attributeValue("AXTitle") or "")
    if title == "SPEAKER NOTES" then
      speakerNotesTab = element
    end
  end

  local children = element:attributeValue("AXChildren")
  if type(children) == "table" then
    for _, child in ipairs(children) do
      if type(child) == "userdata" then
        table.insert(queue, child)
      end
    end
  end
end

if speakerNotesTab then
  local selected = tostring(speakerNotesTab:attributeValue("AXValue") or "")
  if selected ~= "1" and selected ~= "true" then
    speakerNotesTab:performAction("AXPress")
    hs.timer.usleep(140000)
  end
end

if not zoomInButton then
  local frame = targetWindow:frame()
  if not frame or frame.w <= 0 then
    print("error:presenter-frame-not-found")
    return
  end

  local centerX = math.floor(frame.x + frame.w - 17 + 0.5)
  local centerY = math.floor(frame.y + (frame.h * 0.074) + 0.5)
  local originalMouse = hs.mouse.absolutePosition()

  for i = 1, steps do
    hs.eventtap.leftClick({x = centerX, y = centerY})
    if clickDelaySeconds > 0 then
      hs.timer.usleep(math.floor(clickDelaySeconds * 1000000))
    end
  end

  hs.mouse.absolutePosition(originalMouse)
  print(string.format("clicked:%d:x=%d:y=%d:source=coords-fallback", steps, centerX, centerY))
  return
end

local frame = zoomInButton:attributeValue("AXFrame")
local centerX = -1
local centerY = -1
if type(frame) == "table" then
  local fx = frame.x or frame.X or frame[1] or 0
  local fy = frame.y or frame.Y or frame[2] or 0
  local fw = frame.w or frame.W or frame[3] or 0
  local fh = frame.h or frame.H or frame[4] or 0
  centerX = math.floor(fx + (fw / 2) + 0.5)
  centerY = math.floor(fy + (fh / 2) + 0.5)
end

for i = 1, steps do
  zoomInButton:performAction("AXPress")
  if clickDelaySeconds > 0 then
    hs.timer.usleep(math.floor(clickDelaySeconds * 1000000))
  end
end

print(string.format("clicked:%d:x=%d:y=%d:source=axpress", steps, centerX, centerY))
LUA
)"

  hs_result="$("$hs_bin" -c "$hs_script" 2>/dev/null || true)"

  hs_result="$(printf '%s' "$hs_result" | tr -d '\r' | tail -n 1)"
  if [[ -z "$hs_result" ]]; then
    hs_result="error:empty-ax-result"
  fi

  printf '%s\n' "$hs_result"
  [[ "$hs_result" == clicked:* ]]
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

      if oneURL contains "/presentation/d/" and (oneURL contains "/present?" or oneURL contains "/present#" or oneURL contains "/present/" or oneURL ends with "/present") then
        set shouldClose to true
      end if

      if oneURL contains "presenter=true" or oneURL contains "/presenter" then
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

if [[ "$RESTORE_PREVIOUS_SLIDE_ON_REFRESH" == "1" ]]; then
  if has_live_presentation_window_via_hammerspoon; then
    RESTORE_SLIDE_PRESENTATION_OPEN="yes"
    RESTORE_PRESENT_SLIDE_ID_STRICT_VERIFY=1
  elif [[ "$RESTORE_SLIDE_PRESENTATION_OPEN" == "yes" ]]; then
    RESTORE_SLIDE_PRESENTATION_OPEN="url-only"
  fi

  if [[ "$RESTORE_SLIDE_PRESENTATION_OPEN" == "yes" ]]; then
    if RESTORE_SLIDE_NUMBER="$(capture_live_slide_number_with_retries)"; then
      echo "[slides_machine_runner] restore previous slide=$RESTORE_SLIDE_NUMBER"
    elif [[ "$RESTORE_SLIDE_REQUIRE_CAPTURE_WHEN_PRESENTING" == "1" && -z "$RESTORE_PRESENT_SLIDE_ID" ]]; then
      echo "[slides_machine_runner] ERROR: Unable to capture current slide from live presentation (${RESTORE_SLIDE_CAPTURE_RESULT}); refusing refresh to avoid losing slide position." >&2
      exit 1
    fi
  else
    if [[ "$LAST_PRESENTER_WINDOW_CHECK_RESULT" == "absent" || -z "$LAST_PRESENTER_WINDOW_CHECK_RESULT" ]]; then
      RESTORE_SLIDE_PRESENTATION_OPEN="no"
      RESTORE_SLIDE_CAPTURE_RESULT="skipped:no-live-presentation"
    else
      RESTORE_SLIDE_PRESENTATION_OPEN="unknown"
      RESTORE_SLIDE_CAPTURE_RESULT="${LAST_PRESENTER_WINDOW_CHECK_RESULT:-error:presenter-window-check-empty}"
    fi
  fi
fi

ensure_chrome_force_renderer_accessibility

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

if [[ "$SLIDES_LAUNCH_URL" =~ /presentation/d/[^/?#]+/present([/?#]|$) ]]; then
  if ! wait_for_live_present_url 6 >/dev/null; then
    echo "[slides_machine_runner] WARN: present tab not detected after AppleScript open; retrying with macOS open."
    open -a "$CHROME_APP" "$SLIDES_LAUNCH_URL"
    if ! wait_for_live_present_url 8 >/dev/null; then
      echo "[slides_machine_runner] WARN: present tab still not detected; continuing so downstream notes wait can report details."
    fi
  fi
fi

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

on isAudiencePresentationTab(oneTitle, oneURL)
  if oneTitle contains "Presenter view" then return false
  if oneURL does not contain "/presentation/d/" then return false
  if not (oneURL contains "/present?" or oneURL contains "/present#" or oneURL contains "/present/" or oneURL ends with "/present") then return false
  if oneURL contains "presenter=true" then return false
  if oneURL contains "/presenter" then return false
  return true
end isAudiencePresentationTab

on isNotesChromeWindow(oneTitle, oneURL)
  if oneTitle contains "Presenter view" then return true
  return false
end isNotesChromeWindow

on focusAudiencePresentationChromeWindow(processName, chromeAppName)
  set foundWindowIndex to missing value
  set foundTabIndex to missing value

  using terms from application "Google Chrome"
    tell application chromeAppName
      set chromeWindowCount to count of windows

      repeat with i from 1 to chromeWindowCount
        set tabCount to count of tabs of window i

        repeat with tabIndex from 1 to tabCount
          set oneTitle to ""
          set oneURL to ""

          try
            set oneTitle to title of tab tabIndex of window i
          end try

          try
            set oneURL to URL of tab tabIndex of window i
          end try

          if my isAudiencePresentationTab(oneTitle, oneURL) then
            set foundWindowIndex to i
            set foundTabIndex to tabIndex
            exit repeat
          end if
        end repeat

        if foundWindowIndex is not missing value then exit repeat
      end repeat

      if foundWindowIndex is missing value then return false

      set active tab index of window foundWindowIndex to foundTabIndex
      set index of window foundWindowIndex to 1
      activate
    end tell
  end using terms from

  delay 0.2

  tell application "System Events"
    tell process processName
      set frontmost to true
    end tell
  end tell

  return true
end focusAudiencePresentationChromeWindow

on triggerNotesShortcutWithRetries(processName, chromeAppName, maxWaitSeconds, retryIntervalSeconds)
  set startedAt to current date

  repeat
    if my hasNotesChromeWindow(chromeAppName) then return true

    if my focusAudiencePresentationChromeWindow(processName, chromeAppName) then
      my clickFrontWindowCenter(processName)
      delay 0.3
      tell application "System Events"
        tell process processName
          set frontmost to true
          keystroke "s"
        end tell
      end tell
    end if

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

on resolveWindowIndexById(chromeAppName, targetWindowId)
  if targetWindowId is missing value then return missing value

  using terms from application "Google Chrome"
    tell application chromeAppName
      set chromeWindowCount to count of windows
      repeat with i from 1 to chromeWindowCount
        try
          if (id of window i) is targetWindowId then
            return i
          end if
        end try
      end repeat
    end tell
  end using terms from

  return missing value
end resolveWindowIndexById

on setChromeWindowMode(chromeAppName, processName, targetWindowId, modeName)
  if targetWindowId is missing value then return false

  set windowIndex to my resolveWindowIndexById(chromeAppName, targetWindowId)
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
      set windowIndex to my resolveWindowIndexById(chromeAppName, targetWindowId)
      if windowIndex is not missing value then
        try
          using terms from application "Google Chrome"
            tell application chromeAppName
              activate
              set index of window windowIndex to 1
            end tell
          end using terms from
          delay 0.08
        end try
      end if

      tell application "System Events"
        tell process processName
          set frontmost to true
          try
            set value of attribute "AXFullScreen" of window 1 to true
          on error
            keystroke "f" using {command down, control down}
          end try
        end tell
      end tell
      return true
    end if
  end try

  return false
end setChromeWindowMode

on isAXFullscreenByTitleContains(processName, titleToken)
  tell application "System Events"
    tell process processName
      repeat with oneWindow in windows
        set windowTitle to ""
        try
          set windowTitle to value of attribute "AXTitle" of oneWindow
        end try

        if windowTitle contains titleToken then
          try
            if value of attribute "AXFullScreen" of oneWindow is true then
              return true
            end if
          end try
        end if
      end repeat
    end tell
  end tell

  return false
end isAXFullscreenByTitleContains

on isFrontWindowTitleContains(processName, titleToken)
  tell application "System Events"
    tell process processName
      if (count of windows) is 0 then return false

      set frontTitle to ""
      try
        set frontTitle to value of attribute "AXTitle" of window 1
      on error
        try
          set frontTitle to name of window 1
        end try
      end try

      if frontTitle contains titleToken then return true
    end tell
  end tell

  return false
end isFrontWindowTitleContains

on setAXFullscreenByTitleContains(processName, titleToken, targetState)
  tell application "System Events"
    tell process processName
      repeat with oneWindow in windows
        set windowTitle to ""
        try
          set windowTitle to value of attribute "AXTitle" of oneWindow
        end try

        if windowTitle contains titleToken then
          try
            set value of attribute "AXFullScreen" of oneWindow to targetState
            return true
          end try
        end if
      end repeat
    end tell
  end tell

  return false
end setAXFullscreenByTitleContains

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
if notesPlusMethod is not "auto" and notesPlusMethod is not "js" and notesPlusMethod is not "coords" and notesPlusMethod is not "ax" then
  set notesPlusMethod to "auto"
end if

set primaryBounds to csvToBounds(primaryBoundsCSV)
set notesBounds to csvToBounds(notesBoundsCSV)

set notesMethodUsed to "skipped"
set notesFallbackReason to ""
set notesClickDetail to ""
set notesWindowFound to false
set notesWindowWaitResult to "not-requested"
set notesFrontAfterFullscreen to "unknown"

if notesShortcutMaxWait < presenterReadyDelay then
  set notesShortcutMaxWait to presenterReadyDelay
end if

if notesShortcutMaxWait < notesShortcutRetryInterval then
  set notesShortcutMaxWait to notesShortcutRetryInterval
end if

my waitForProcess(chromeApp, waitTimeout)
my waitForWindowCount(chromeApp, 1, waitTimeout)
my focusAudiencePresentationChromeWindow(chromeApp, chromeApp)

my waitForProcess(chromeApp, waitTimeout)
tell application "System Events"
  tell process chromeApp
    set frontmost to true
    set slidesWindow to window 1

    if launchFromEditMode is "1" then
      my clickWindowCenter(chromeApp, slidesWindow)
      keystroke return using {command down}
      delay launchDelay
      my focusAudiencePresentationChromeWindow(chromeApp, chromeApp)
    end if

    if notesViaShortcut is "1" then
      my focusAudiencePresentationChromeWindow(chromeApp, chromeApp)
      delay presenterReadyDelay
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
set slidesChromeId to missing value
set notesChromeId to missing value

using terms from application "Google Chrome"
  tell application chromeApp
    set chromeWindowCount to count of windows

    repeat with i from 1 to chromeWindowCount
      set oneTitle to ""
      set oneURL to ""
      set oneWindowId to missing value

      try
        set oneTitle to title of active tab of window i
      end try

      try
        set oneURL to URL of active tab of window i
      end try

      try
        set oneWindowId to id of window i
      end try

      if notesChromeIndex is missing value and my isNotesChromeWindow(oneTitle, oneURL) then
        set notesChromeIndex to i
        set notesChromeId to oneWindowId
      end if

      if slidesChromeIndex is missing value and my isAudiencePresentationTab(oneTitle, oneURL) then
        set slidesChromeIndex to i
        set slidesChromeId to oneWindowId
      end if
    end repeat

    if slidesChromeIndex is missing value and chromeWindowCount is greater than 0 then
      set slidesChromeIndex to 1
      try
        set slidesChromeId to id of window 1
      end try
    end if

    if notesChromeId is not missing value and slidesChromeId is not missing value and notesChromeId is slidesChromeId then
      set notesChromeIndex to missing value
      set notesChromeId to missing value
    end if
  end tell
end using terms from

my waitForProcess(chromeApp, waitTimeout)

set slidesChromeIndex to my resolveWindowIndexById(chromeApp, slidesChromeId)
set notesChromeIndex to my resolveWindowIndexById(chromeApp, notesChromeId)

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

if fullscreenPrimary is "1" and slidesChromeId is not missing value then
  my setChromeWindowMode(chromeApp, chromeApp, slidesChromeId, "fullscreen")
  delay launchDelay
end if

set notesChromeIndex to my resolveWindowIndexById(chromeApp, notesChromeId)

if notesChromeIndex is not missing value then
  if fullscreenNotes is "1" and notesChromeId is not missing value then
    my setChromeWindowMode(chromeApp, chromeApp, notesChromeId, "fullscreen")
    delay 0.15
    if my isAXFullscreenByTitleContains(chromeApp, "Presenter view") is false then
      my setAXFullscreenByTitleContains(chromeApp, "Presenter view", true)
      delay 0.15
    end if
    delay launchDelay
  end if

  if my isFrontWindowTitleContains(chromeApp, "Presenter view") then
    set notesFrontAfterFullscreen to "yes"
  else
    set notesFrontAfterFullscreen to "no"
    if notesFallbackReason is "" then
      set notesFallbackReason to "notes-not-front-after-fullscreen"
    else
      set notesFallbackReason to notesFallbackReason & " | notes-not-front-after-fullscreen"
    end if
  end if

  set notesChromeIndex to my resolveWindowIndexById(chromeApp, notesChromeId)

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
        if notesFrontAfterFullscreen is "yes" then
          set coordResult to my clickNotesPlusByWindowBounds(chromeApp, chromeApp, notesChromeIndex, notesPlusClickSteps, notesPlusClickDelay, notesPlusButtonRightOffset, notesPlusButtonTopOffset)
        else
          set coordResult to "error:notes-not-front"
        end if

        if my startsWith(coordResult, "clicked:") then
          set notesMethodUsed to "coords"
          set notesClickDetail to coordResult
        else
          if notesFallbackReason is "" then
            set notesFallbackReason to coordResult
          else
            set notesFallbackReason to notesFallbackReason & " | " & coordResult
          end if

          if notesFrontAfterFullscreen is "yes" then
            set coordBoundsResult to my clickNotesPlusByBounds(chromeApp, notesBounds, notesPlusClickSteps, notesPlusClickDelay, notesPlusButtonRightOffset, notesPlusButtonTopOffset, "config")
          else
            set coordBoundsResult to "error:notes-not-front"
          end if

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

      if notesMethodUsed is "failed" and (notesPlusMethod is "auto" or notesPlusMethod is "coords") and notesChromeId is not missing value then
        my setChromeWindowMode(chromeApp, chromeApp, notesChromeId, "normal")
        delay 0.25
        set notesChromeIndex to my resolveWindowIndexById(chromeApp, notesChromeId)
        if notesChromeIndex is not missing value then
          using terms from application "Google Chrome"
            tell application chromeApp
              set bounds of window notesChromeIndex to notesBounds
              try
                set mode of window notesChromeIndex to "normal"
              end try
            end tell
          end using terms from

          delay 0.2
          set normalCoordResult to my clickNotesPlusByWindowBounds(chromeApp, chromeApp, notesChromeIndex, notesPlusClickSteps, notesPlusClickDelay, notesPlusButtonRightOffset, notesPlusButtonTopOffset)
          if my startsWith(normalCoordResult, "clicked:") then
            set notesMethodUsed to "coords"
            set notesClickDetail to normalCoordResult & ":fallback=normal"
          else
            if notesFallbackReason is "" then
              set notesFallbackReason to normalCoordResult
            else
              set notesFallbackReason to notesFallbackReason & " | " & normalCoordResult
            end if
          end if
        end if

        if fullscreenNotes is "1" and notesChromeId is not missing value then
          my setChromeWindowMode(chromeApp, chromeApp, notesChromeId, "fullscreen")
          delay 0.15
          if my isAXFullscreenByTitleContains(chromeApp, "Presenter view") is false then
            my setAXFullscreenByTitleContains(chromeApp, "Presenter view", true)
            delay 0.15
          end if
          delay launchDelay
        end if
      end if
    else
      set notesMethodUsed to "skipped"
    end if
  end if
end if

set notesChromeIndex to my resolveWindowIndexById(chromeApp, notesChromeId)

if expectNotesWindow is "1" and notesChromeIndex is missing value then
  if notesFallbackReason is "" then
    set notesFallbackReason to "notes-window-not-found"
  else
    set notesFallbackReason to notesFallbackReason & " | notes-window-not-found"
  end if
end if

return "NOTES_METHOD_CONFIG=" & notesPlusMethod & linefeed & "NOTES_METHOD_USED=" & notesMethodUsed & linefeed & "NOTES_CLICK_DETAIL=" & notesClickDetail & linefeed & "NOTES_WINDOW_EXPECTED=" & expectNotesWindow & linefeed & "NOTES_WINDOW_FOUND=" & notesWindowFound & linefeed & "NOTES_WINDOW_WAIT_RESULT=" & notesWindowWaitResult & linefeed & "NOTES_FRONT_AFTER_FULLSCREEN=" & notesFrontAfterFullscreen & linefeed & "NOTES_SHORTCUT_WAIT_SECONDS=" & notesShortcutMaxWait & linefeed & "NOTES_FALLBACK_REASON=" & notesFallbackReason
APPLESCRIPT
)"

notes_method_config="$NOTES_PLUS_METHOD"
notes_method_used=""
notes_click_detail=""
notes_window_expected=""
notes_window_found=""
notes_window_wait_result=""
notes_front_after_fullscreen=""
notes_shortcut_wait_seconds=""
notes_fallback_reason=""

while IFS= read -r summary_line; do
  [[ -z "$summary_line" ]] && continue

  summary_key="${summary_line%%=*}"
  summary_value="${summary_line#*=}"

  case "$summary_key" in
    NOTES_METHOD_CONFIG) notes_method_config="$summary_value" ;;
    NOTES_METHOD_USED) notes_method_used="$summary_value" ;;
    NOTES_CLICK_DETAIL) notes_click_detail="$summary_value" ;;
    NOTES_WINDOW_EXPECTED) notes_window_expected="$summary_value" ;;
    NOTES_WINDOW_FOUND) notes_window_found="$summary_value" ;;
    NOTES_WINDOW_WAIT_RESULT) notes_window_wait_result="$summary_value" ;;
    NOTES_FRONT_AFTER_FULLSCREEN) notes_front_after_fullscreen="$summary_value" ;;
    NOTES_SHORTCUT_WAIT_SECONDS) notes_shortcut_wait_seconds="$summary_value" ;;
    NOTES_FALLBACK_REASON) notes_fallback_reason="$summary_value" ;;
  esac
done <<< "$apple_summary"

should_try_axpress=0
if [[ "$NOTES_PLUS_CLICK_STEPS" =~ ^[0-9]+$ ]] && (( NOTES_PLUS_CLICK_STEPS > 0 )); then
  if [[ "$notes_method_config" == "ax" ]]; then
    should_try_axpress=1
  elif [[ "$notes_method_config" == "auto" ]]; then
    if [[ "$notes_method_used" != "js" && "$notes_method_used" != "coords" && "$notes_method_used" != "skipped" ]]; then
      should_try_axpress=1
    fi
  fi
fi

if (( should_try_axpress == 1 )); then
  axpress_result="$(click_notes_plus_via_hammerspoon_axpress || true)"
  if [[ "$axpress_result" == clicked:* ]]; then
    notes_method_used="ax"
    notes_click_detail="$axpress_result"
  else
    if [[ -n "$notes_fallback_reason" ]]; then
      notes_fallback_reason="$notes_fallback_reason | $axpress_result"
    else
      notes_fallback_reason="$axpress_result"
    fi
    if [[ "$notes_method_config" == "ax" ]]; then
      notes_method_used="failed"
    fi
  fi
fi

if [[ "$RESTORE_SLIDE_NUMBER" =~ ^[0-9]+$ ]] && (( RESTORE_SLIDE_NUMBER > 0 )); then
  if ! RESTORE_SLIDE_RESULT="$(restore_slide_number_via_hammerspoon "$RESTORE_SLIDE_NUMBER")"; then
    echo "[slides_machine_runner] ERROR: Unable to restore previous slide ($RESTORE_SLIDE_RESULT)." >&2
    exit 1
  fi
  sleep 0.2
elif [[ -n "$RESTORE_PRESENT_SLIDE_ID" && "$RESTORE_PRESENT_SLIDE_ID_STRICT_VERIFY" == "1" ]]; then
  if ! RESTORE_SLIDE_RESULT="$(verify_live_present_slide_id "$RESTORE_PRESENT_SLIDE_ID")"; then
    echo "[slides_machine_runner] ERROR: Relaunched deck did not return to the original slide token ($RESTORE_SLIDE_RESULT)." >&2
    exit 1
  fi
  sleep 0.2
elif [[ -n "$RESTORE_PRESENT_SLIDE_ID" ]]; then
  RESTORE_SLIDE_RESULT="skipped-url-token-verify:no-live-presenter-window"
fi

echo "[slides_machine_runner] RESTORE_PREVIOUS_SLIDE_ON_REFRESH=$RESTORE_PREVIOUS_SLIDE_ON_REFRESH"
echo "[slides_machine_runner] RESTORE_SLIDE_PRESENTATION_OPEN=$RESTORE_SLIDE_PRESENTATION_OPEN"
echo "[slides_machine_runner] RESTORE_SLIDE_CAPTURE_RESULT=$RESTORE_SLIDE_CAPTURE_RESULT"
echo "[slides_machine_runner] RESTORE_PRESENT_SLIDE_ID=${RESTORE_PRESENT_SLIDE_ID:-none}"
echo "[slides_machine_runner] RESTORE_PRESENT_SLIDE_ID_STRICT_VERIFY=$RESTORE_PRESENT_SLIDE_ID_STRICT_VERIFY"
echo "[slides_machine_runner] RESTORE_SLIDE_NUMBER=${RESTORE_SLIDE_NUMBER:-none}"
echo "[slides_machine_runner] RESTORE_SLIDE_RESULT=$RESTORE_SLIDE_RESULT"

echo "[slides_machine_runner] NOTES_METHOD_CONFIG=$notes_method_config"
echo "[slides_machine_runner] NOTES_METHOD_USED=$notes_method_used"
echo "[slides_machine_runner] NOTES_CLICK_DETAIL=$notes_click_detail"
echo "[slides_machine_runner] NOTES_WINDOW_EXPECTED=$notes_window_expected"
echo "[slides_machine_runner] NOTES_WINDOW_FOUND=$notes_window_found"
echo "[slides_machine_runner] NOTES_WINDOW_WAIT_RESULT=$notes_window_wait_result"
echo "[slides_machine_runner] NOTES_FRONT_AFTER_FULLSCREEN=$notes_front_after_fullscreen"
echo "[slides_machine_runner] NOTES_SHORTCUT_WAIT_SECONDS=$notes_shortcut_wait_seconds"
echo "[slides_machine_runner] NOTES_FALLBACK_REASON=$notes_fallback_reason"
