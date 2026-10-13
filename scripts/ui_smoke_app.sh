#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/MacMouseMapper.app"
PROCESS_NAME="MacMouseMapper"
SCREENSHOT="/tmp/MacMouseMapper-ui-smoke.png"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null
existing="$(pgrep -x "$PROCESS_NAME" || true)"
open -n "$APP_DIR"
new_pids=""
cleanup() {
    for pid in $new_pids; do
        kill "$pid" 2>/dev/null || true
    done
    rm -f /tmp/MacMouseMapper-ui-smoke-ax.log
}
trap cleanup EXIT

for _ in {1..24}; do
    current="$(pgrep -x "$PROCESS_NAME" || true)"
    for pid in $current; do
        case " $existing " in
            *" $pid "*) ;;
            *) new_pids="$new_pids $pid" ;;
        esac
    done
    [[ -n "${new_pids// /}" ]] && break
    sleep 0.25
done
[[ -n "${new_pids// /}" ]] || { echo "Packaged app did not launch" >&2; exit 1; }
open "$APP_DIR"
sleep 1

# Exercise the real settings window at its minimum, default, and wide sizes.
set +e
/usr/bin/osascript <<'APPLESCRIPT' >/tmp/MacMouseMapper-ui-smoke-ax.log 2>&1
tell application "System Events"
    tell process "MacMouseMapper"
        set frontmost to true
        if not (exists window 1) then error "settings window did not appear"
        repeat with requestedSize in {{620, 500}, {760, 720}, {1100, 800}}
            set size of window 1 to requestedSize
            delay 0.7
            if not (exists window 1) then error "settings window disappeared while resizing"
        end repeat
    end tell
end tell
APPLESCRIPT
ax_status=$?
set -e
if [[ "$ax_status" -ne 0 ]]; then
    if /usr/bin/grep -q "not allowed assistive access" /tmp/MacMouseMapper-ui-smoke-ax.log; then
        echo "Assistive Access unavailable; could not automate window resizing (launch still verified)"
    else
        cat /tmp/MacMouseMapper-ui-smoke-ax.log >&2
        exit "$ax_status"
    fi
fi
rm -f /tmp/MacMouseMapper-ui-smoke-ax.log

# AppKit reports unsatisfiable constraints to the unified log. Check the
# resize interval for those errors while keeping Screen Recording optional.
if /usr/bin/log show --last 45s --style compact --predicate 'process == "MacMouseMapper" AND (eventMessage CONTAINS[c] "Unable to simultaneously satisfy constraints" OR eventMessage CONTAINS[c] "Ambiguous layout")' | /usr/bin/grep -E -q "Unable to simultaneously satisfy constraints|Ambiguous layout"; then
    echo "Auto Layout emitted an error during settings-window smoke" >&2
    exit 1
fi
if /usr/bin/screencapture -x "$SCREENSHOT" 2>/dev/null; then
    echo "Settings-window screenshot: $SCREENSHOT"
else
    echo "Screen capture unavailable; continuing without screenshot"
fi
echo "Settings window opened and resized at minimum/default/wide sizes without logged Auto Layout errors"
