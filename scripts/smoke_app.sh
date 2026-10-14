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

icon_path="$APP_DIR/Contents/Resources/MacMouseMapper.icns"
[[ -s "$icon_path" ]] || { echo "Missing packaged app icon: $icon_path" >&2; exit 1; }
icon_decode_root="$(mktemp -d)"
iconset_path="$icon_decode_root/MacMouseMapper.iconset"
/usr/bin/iconutil -c iconset "$icon_path" -o "$iconset_path"
for representation in icon_16x16.png icon_16x16@2x.png icon_512x512.png icon_512x512@2x.png; do
    [[ -s "$iconset_path/$representation" ]] || {
        echo "App icon is missing representation: $representation" >&2
        rm -rf "$icon_decode_root"
        exit 1
    }
done
/usr/bin/sips -g pixelWidth -g pixelHeight "$iconset_path/icon_512x512@2x.png" >/dev/null
icon_reference="$(/usr/bin/plutil -extract CFBundleIconFile raw -o - "$APP_DIR/Contents/Info.plist")"
[[ "$icon_reference" == "MacMouseMapper.icns" ]] || {
    echo "CFBundleIconFile does not reference MacMouseMapper.icns: $icon_reference" >&2
    rm -rf "$icon_decode_root"
    exit 1
}
rm -rf "$icon_decode_root"
echo "Validated packaged MacMouseMapper.icns representations and Info.plist reference"

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
