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
  NOTES_PLUS_CLICK_STEPS=0
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
NOTES_PLUS_CLICK_DELAY_SECONDS="${NOTES_PLUS_CLICK_DELAY_SECONDS:-${NOTES_ZOOM_STEP_DELAY_SECONDS:-0.08}}"
NOTES_PLUS_BUTTON_RIGHT_OFFSET="${NOTES_PLUS_BUTTON_RIGHT_OFFSET:-56}"
NOTES_PLUS_BUTTON_TOP_OFFSET="${NOTES_PLUS_BUTTON_TOP_OFFSET:-164}"
OPEN_RETRY_COUNT="${OPEN_RETRY_COUNT:-3}"
OPEN_RETRY_DELAY_SECONDS="${OPEN_RETRY_DELAY_SECONDS:-1.0}"
WINDOW_WAIT_TIMEOUT_SECONDS="${WINDOW_WAIT_TIMEOUT_SECONDS:-20}"

SLIDES_PRESENT_URL="${SLIDES_PRESENT_URL:-}"
SLIDES_NOTES_URL="${SLIDES_NOTES_URL:-}"
SLIDES_SOURCE_URL="${SLIDES_SOURCE_URL:-}"
SLIDES_LAUNCH_URL=""
SOURCE_DECK_ID=""

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

export CHROME_APP
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
export NOTES_PLUS_CLICK_STEPS
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

/usr/bin/osascript <<'APPLESCRIPT'
on csvToBounds(csvText)
  set oldDelims to AppleScript's text item delimiters
  set AppleScript's text item delimiters to ","
  set rawParts to text items of csvText
  set AppleScript's text item delimiters to oldDelims

  if (count of rawParts) is not 4 then
    error "Bounds must be 4 comma-separated integers: " & csvText
  end if

  set outList to {}
  repeat with onePart in rawParts
    set end of outList to (onePart as integer)
  end repeat

  return outList
end csvToBounds

on setWindowBounds(processName, targetWindow, boundValues)
  set leftEdge to item 1 of boundValues
  set topEdge to item 2 of boundValues
  set rightEdge to item 3 of boundValues
  set bottomEdge to item 4 of boundValues

  set targetWidth to rightEdge - leftEdge
  set targetHeight to bottomEdge - topEdge

  tell application "System Events"
    tell process processName
      set value of attribute "AXPosition" of targetWindow to {leftEdge, topEdge}
      set value of attribute "AXSize" of targetWindow to {targetWidth, targetHeight}
    end tell
  end tell
end setWindowBounds

on raiseWindow(processName, targetWindow)
  tell application "System Events"
    tell process processName
      try
        perform action "AXRaise" of targetWindow
      on error
        set frontmost to true
      end try
    end tell
  end tell
end raiseWindow

on setWindowFullscreen(processName, targetWindow)
  tell application "System Events"
    tell process processName
      try
        set value of attribute "AXFullScreen" of targetWindow to true
      on error
        my raiseWindow(processName, targetWindow)
        delay 0.15
        keystroke "f" using {command down, control down}
      end try
    end tell
  end tell
end setWindowFullscreen

on setSlidesWindowFullscreen(processName)
  tell application "System Events"
    tell process processName
      repeat with oneWindow in windows
        set oneTitle to ""
        try
          set oneTitle to name of oneWindow
        end try

        if oneTitle contains "Google Slides" and oneTitle does not contain "Presenter view" then
          my setWindowFullscreen(processName, oneWindow)
          return true
        end if
      end repeat
    end tell
  end tell

  return false
end setSlidesWindowFullscreen

on setNotesWindowFullscreen(processName)
  tell application "System Events"
    tell process processName
      repeat with oneWindow in windows
        set oneTitle to ""
        try
          set oneTitle to name of oneWindow
        end try

        if oneTitle contains "Presenter view" and oneTitle contains "Google Slides" then
          my setWindowFullscreen(processName, oneWindow)
          return true
        end if
      end repeat
    end tell
  end tell

  return false
end setNotesWindowFullscreen

on clickNotesPlusButton(processName, plusClicks, clickDelaySeconds, rightOffset, topOffset)
  if plusClicks is less than or equal to 0 then
    return true
  end if

  set notesWindow to missing value

  tell application "System Events"
    tell process processName
      repeat with oneWindow in windows
        set oneTitle to ""
        try
          set oneTitle to name of oneWindow
        end try

        if oneTitle contains "Presenter view" and oneTitle contains "Google Slides" then
          set notesWindow to oneWindow
          exit repeat
        end if
      end repeat
    end tell
  end tell

  if notesWindow is missing value then
    return false
  end if

  tell application "System Events"
    tell process processName
      set frontmost to true
      my raiseWindow(processName, notesWindow)

      set winPos to value of attribute "AXPosition" of notesWindow
      set winSize to value of attribute "AXSize" of notesWindow
    end tell
  end tell

  set clickX to (item 1 of winPos) + (item 1 of winSize) - rightOffset
  set clickY to (item 2 of winPos) + topOffset

  delay 0.15

  tell application "System Events"
    tell process processName
      set frontmost to true
      repeat plusClicks times
        click at {clickX, clickY}
        delay clickDelaySeconds
      end repeat
    end tell
  end tell

  return true
end clickNotesPlusButton

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

    if currentCount is greater than or equal to minCount then
      return
    end if

    if (current date) - startedAt > timeoutSeconds then
      error "Timed out waiting for " & minCount & " Chrome window(s)."
    end if

    delay 0.1
  end repeat
end waitForWindowCount

on waitForNotesWindowOrTimeout(processName, minCount, timeoutSeconds)
  set startedAt to current date

  repeat
    set currentCount to 0
    set foundPresenterWindow to false

    try
      tell application "System Events"
        tell process processName
          set currentCount to count of windows

          repeat with oneWindow in windows
            try
              if (name of oneWindow) contains "Presenter view" then
                set foundPresenterWindow to true
                exit repeat
              end if
            end try
          end repeat
        end tell
      end tell
    end try

    if currentCount is greater than or equal to minCount then
      return
    end if

    if foundPresenterWindow is true then
      return
    end if

    if (current date) - startedAt > timeoutSeconds then
      return
    end if

    delay 0.1
  end repeat
end waitForNotesWindowOrTimeout

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

        if oneTitle contains "Presenter view" and oneURL starts with "about:blank" then
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
    if my hasNotesChromeWindow(chromeAppName) then
      return true
    end if

    if (current date) - startedAt > timeoutSeconds then
      return false
    end if

    delay 0.1
  end repeat
end waitForNotesChromeWindow

on triggerNotesShortcutWithRetries(processName, chromeAppName, slidesWindow, maxWaitSeconds, retryIntervalSeconds)
  set startedAt to current date

  repeat
    if my hasNotesChromeWindow(chromeAppName) then
      return true
    end if

    my clickWindowCenter(processName, slidesWindow)
    tell application "System Events"
      tell process processName
        set frontmost to true
        keystroke "s"
      end tell
    end tell

    delay retryIntervalSeconds

    if my hasNotesChromeWindow(chromeAppName) then
      return true
    end if

    if (current date) - startedAt > maxWaitSeconds then
      return false
    end if
  end repeat
end triggerNotesShortcutWithRetries

on waitForProcess(processName, timeoutSeconds)
  set startedAt to current date

  repeat
    tell application "System Events"
      if exists process processName then
        return
      end if
    end tell

    if (current date) - startedAt > timeoutSeconds then
      error "Timed out waiting for process: " & processName
    end if

    delay 0.1
  end repeat
end waitForProcess

set chromeApp to system attribute "CHROME_APP"
set primaryBoundsCSV to system attribute "PRIMARY_BOUNDS"
set notesBoundsCSV to system attribute "NOTES_BOUNDS"
set fullscreenPrimary to system attribute "FULLSCREEN_PRIMARY"
set fullscreenNotes to system attribute "FULLSCREEN_NOTES"
set launchDelayRaw to system attribute "LAUNCH_DELAY_SECONDS"
set presenterReadyDelayRaw to system attribute "PRESENTER_READY_DELAY_SECONDS"
set notesShortcutRetryIntervalRaw to system attribute "NOTES_SHORTCUT_RETRY_INTERVAL_SECONDS"
set notesPlusClickStepsRaw to system attribute "NOTES_PLUS_CLICK_STEPS"
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
set notesPlusClickSteps to notesPlusClickStepsRaw as integer
set notesPlusClickDelay to notesPlusClickDelayRaw as number
set notesPlusButtonRightOffset to notesPlusButtonRightOffsetRaw as integer
set notesPlusButtonTopOffset to notesPlusButtonTopOffsetRaw as integer
set waitTimeout to timeoutRaw as number

set primaryBounds to csvToBounds(primaryBoundsCSV)
set notesBounds to csvToBounds(notesBoundsCSV)

my waitForProcess(chromeApp, waitTimeout)
my waitForWindowCount(chromeApp, 1, waitTimeout)

my waitForProcess(chromeApp, waitTimeout)
tell application "System Events"
  tell process chromeApp
    set frontmost to true
    set slidesWindow to window 1
    my setWindowBounds(chromeApp, slidesWindow, primaryBounds)
    my raiseWindow(chromeApp, slidesWindow)
    my clickWindowCenter(chromeApp, slidesWindow)

    if launchFromEditMode is "1" then
      keystroke return using {command down}
      delay launchDelay
      my clickWindowCenter(chromeApp, slidesWindow)
    end if

    if notesViaShortcut is "1" then
      -- Try opening notes immediately, retrying quickly until it appears or timeout.
      my triggerNotesShortcutWithRetries(chromeApp, chromeApp, slidesWindow, presenterReadyDelay, notesShortcutRetryInterval)
      delay launchDelay
    end if
  end tell
end tell

if expectNotesWindow is "1" then
  my waitForNotesChromeWindow(chromeApp, waitTimeout)
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

      if notesChromeIndex is missing value and oneTitle contains "Presenter view" and oneURL starts with "about:blank" then
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
    end tell
  end using terms from
end if

if fullscreenPrimary is "1" and slidesChromeIndex is not missing value then
  my setSlidesWindowFullscreen(chromeApp)
  delay launchDelay
end if

if fullscreenNotes is "1" and notesChromeIndex is not missing value then
  set notesFullscreenIndex to missing value

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

        if oneTitle contains "Presenter view" and oneURL starts with "about:blank" then
          set notesFullscreenIndex to i
          exit repeat
        end if
      end repeat
    end tell
  end using terms from

  if notesFullscreenIndex is not missing value then
    my setNotesWindowFullscreen(chromeApp)

    if notesPlusClickSteps > 0 then
      my clickNotesPlusButton(chromeApp, notesPlusClickSteps, notesPlusClickDelay, notesPlusButtonRightOffset, notesPlusButtonTopOffset)
    end if

    delay launchDelay
  end if
end if
APPLESCRIPT
