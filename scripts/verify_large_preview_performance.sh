#!/usr/bin/env bash

set -euo pipefail

APP="${APP:-/Applications/Surge Shallow.app}"
PROCESS_NAME="SurgeShallow"
PREVIEW="${PREVIEW:-$HOME/Library/Application Support/Surge Profile Relay/Preview/Surge-Profile-Relay-Shared.dconf}"
MAX_READY_SECONDS="${MAX_READY_SECONDS:-3.0}"

cleanup() {
    pkill -x "$PROCESS_NAME" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
    echo "Missing app: $APP" >&2
    exit 2
fi
if [[ ! -f "$PREVIEW" ]]; then
    echo "Missing shared preview: $PREVIEW" >&2
    exit 2
fi

preview_bytes="$(stat -f '%z' "$PREVIEW")"
preview_lines="$(wc -l < "$PREVIEW" | tr -d ' ')"
if (( preview_bytes < 100000 || preview_lines < 3000 )); then
    echo "Preview is too small for the large-document regression: ${preview_bytes} bytes, ${preview_lines} lines" >&2
    exit 2
fi

cleanup
open -na "$APP" --args --verification-mode
for _ in $(jot 20); do
    pgrep -x "$PROCESS_NAME" >/dev/null && break
    sleep 0.1
done
pgrep -x "$PROCESS_NAME" >/dev/null || {
    echo "App failed to launch" >&2
    exit 1
}

window_count=0
for _ in $(jot 30); do
    window_count="$(osascript -e 'tell application "System Events" to tell first application process whose bundle identifier is "com.surgeprofilerelay.app" to count windows' 2>/dev/null || echo 0)"
    (( window_count > 0 )) && break
    sleep 0.1
done
if (( window_count == 0 )); then
    echo "App launched without a main window" >&2
    exit 1
fi

osascript <<'APPLESCRIPT'
tell application "System Events"
    tell first application process whose bundle identifier is "com.surgeprofilerelay.app"
        set frontmost to true
        set value of attribute "AXSelected" of row 5 of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1 to true
        delay 0.5
    end tell
end tell
APPLESCRIPT

start_time="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
    tell first application process whose bundle identifier is "com.surgeprofilerelay.app"
        set profileScroll to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
        set previewButton to missing value
        repeat with currentButton in buttons of profileScroll
            try
                if value of attribute "AXIdentifier" of currentButton is "shared-profile-preview" then
                    set previewButton to currentButton
                    exit repeat
                end if
            end try
        end repeat
        if previewButton is missing value then set previewButton to button 9 of profileScroll
        perform action "AXPress" of previewButton
    end tell
end tell
APPLESCRIPT

sheet_count=0
for _ in $(jot 30); do
    sheet_count="$(osascript -e 'tell application "System Events" to tell first application process whose bundle identifier is "com.surgeprofilerelay.app" to count sheets of window 1' 2>/dev/null || echo 0)"
    (( sheet_count > 0 )) && break
    sleep 0.1
done

end_time="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
ready_seconds="$(perl -e 'printf "%.3f", $ARGV[1]-$ARGV[0]' "$start_time" "$end_time")"

accessible_characters=0
if (( sheet_count > 0 )); then
    accessible_characters="$(osascript <<'APPLESCRIPT'
tell application "System Events"
    tell first application process whose bundle identifier is "com.surgeprofilerelay.app"
        set longestTextLength to 0
        set allElements to entire contents of sheet 1 of window 1
        repeat with currentElement in allElements
            try
                set currentRole to value of attribute "AXRole" of currentElement
                if currentRole is "AXStaticText" or currentRole is "AXTextArea" then
                    set currentText to ""
                    try
                        set currentText to value of currentElement
                    end try
                    if currentText is missing value or currentText is "" then
                        try
                            set currentText to name of currentElement
                        end try
                    end if
                    if currentText is not missing value then
                        set currentLength to length of currentText
                        if currentLength > longestTextLength then set longestTextLength to currentLength
                    end if
                end if
            end try
        end repeat
        return longestTextLength
    end tell
end tell
APPLESCRIPT
)"
fi

echo "preview_bytes=$preview_bytes"
echo "preview_lines=$preview_lines"
echo "preview_ready_seconds=$ready_seconds"
echo "sheet_count=$sheet_count"
echo "accessible_characters=$accessible_characters"

awk -v elapsed="$ready_seconds" -v limit="$MAX_READY_SECONDS" \
    -v sheets="$sheet_count" -v characters="$accessible_characters" '
    BEGIN {
        if (elapsed <= limit && sheets == 1 && characters >= 100000) exit 0
        exit 1
    }
'
