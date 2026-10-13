#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/MacMouseMapper.app"
PROCESS_NAME="MacMouseMapper"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null
for image in accessibility-request.png accessibility-toggle.png; do
    image_path="$APP_DIR/Contents/Resources/$image"
    [[ -f "$image_path" ]] || { echo "Missing packaged resource: $image" >&2; exit 1; }
    /usr/bin/sips -g pixelWidth -g pixelHeight "$image_path" >/dev/null
    echo "Decoded packaged resource: $image"
done

existing="$(pgrep -x "$PROCESS_NAME" || true)"
open -n "$APP_DIR"
new_pids=""
for _ in {1..20}; do
    current="$(pgrep -x "$PROCESS_NAME" || true)"
    for pid in $current; do
        case " $existing " in
            *" $pid "*) ;;
            *) new_pids="$new_pids $pid" ;;
        esac
    done
    if [[ -n "${new_pids// /}" ]]; then
        break
    fi
    sleep 0.25
done

if [[ -z "${new_pids// /}" ]]; then
    echo "Packaged app did not launch" >&2
    exit 1
fi

# A second normal open request exercises applicationShouldHandleReopen and
# brings the settings window forward without a test-only production flag.
open "$APP_DIR"
sleep 3
for pid in $new_pids; do
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Packaged app exited before smoke interval (pid $pid)" >&2
        exit 1
    fi
done
echo "Packaged app launched, reopened, and remained alive for 3 seconds (pid(s):$new_pids)"
for pid in $new_pids; do
    kill "$pid" 2>/dev/null || true
done
