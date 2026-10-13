#!/bin/bash
set -euo pipefail

# Resolve the repository once so every build, launch, and identity check points
# at the same checkout, even when this script is invoked through a symlink.
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
    SOURCE_DIR="$(CDPATH= cd -P -- "$(dirname -- "$SOURCE")" && pwd -P)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" == /* ]] || SOURCE="$SOURCE_DIR/$SOURCE"
done
SCRIPT_DIR="$(CDPATH= cd -P -- "$(dirname -- "$SOURCE")" && pwd -P)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)"
APP_DIR="$ROOT_DIR/build/MacMouseMapper.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/MacMouseMapper"
PROCESS_NAME="MacMouseMapper"
POLL_INTERVAL=0.25
TERMINATION_ATTEMPTS=32
LAUNCH_ATTEMPTS=40

# pgrep -x is intentionally exact: do not broaden this to a command-line or
# substring match that could terminate an unrelated process.
exact_pids() {
    pgrep -x "$PROCESS_NAME" 2>/dev/null | tr '\n' ' ' || true
}

has_pids() {
    [[ -n "${1// /}" ]]
}

pid_in_list() {
    local pid_list="$1"
    local pid="$2"
    case " $pid_list " in
        *" $pid "*) return 0 ;;
        *) return 1 ;;
    esac
}

paths_match() {
    local expected="$1"
    local observed="$2"
    [[ "$expected" == "$observed" ]] && return 0
    if [[ -e "$expected" && -e "$observed" ]]; then
        local expected_identity
        local observed_identity
        expected_identity="$(stat -f '%d:%i' "$expected" 2>/dev/null || true)"
        observed_identity="$(stat -f '%d:%i' "$observed" 2>/dev/null || true)"
        if [[ -n "$expected_identity" && "$expected_identity" == "$observed_identity" ]]; then
            return 0
        fi
    fi
    return 1
}

# lsof reports the executable text image without relying on a command-line
# substring. ps is a fallback for systems where lsof cannot inspect the pid.
process_executable_path() {
    local pid="$1"
    local path=""
    local field

    if [[ -x /usr/sbin/lsof ]]; then
        while IFS= read -r field; do
            case "$field" in
                n*)
                    path="${field#n}"
                    break
                    ;;
            esac
        done < <(/usr/sbin/lsof -a -p "$pid" -d txt -Fn 2>/dev/null || true)
    fi

    if [[ -z "$path" ]]; then
        local command_line
        command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        path="${command_line%% *}"
    fi

    if [[ -n "$path" && -e "$path" ]]; then
        local directory="${path%/*}"
        local filename="${path##*/}"
        [[ "$directory" == "$path" ]] && directory="."
        if directory="$(CDPATH= cd -- "$directory" 2>/dev/null && pwd -P)"; then
            printf '%s/%s\n' "$directory" "$filename"
            return
        fi
    fi
    printf '%s\n' "$path"
}

print_exact_processes() {
    local pid
    for pid in $(exact_pids); do
        printf '  pid %s executable %s\n' "$pid" "$(process_executable_path "$pid")"
    done
}

existing_pids="$(exact_pids)"
if has_pids "$existing_pids"; then
    echo "Requesting graceful termination of exact $PROCESS_NAME process(es): $existing_pids"
    for pid in $existing_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            # SIGTERM is the only termination signal used here. If an app does
            # not exit in time, stop and ask the developer to close it by hand.
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done

    for ((attempt = 0; attempt < TERMINATION_ATTEMPTS; attempt++)); do
        remaining_pids="$(exact_pids)"
        if ! has_pids "$remaining_pids"; then
            break
        fi
        sleep "$POLL_INTERVAL"
    done
    remaining_pids="$(exact_pids)"
    if has_pids "$remaining_pids"; then
        echo "MacMouseMapper did not exit after a graceful termination request." >&2
        echo "Close the remaining exact process(es) from MacMouseMapper's menu, then rerun:" >&2
        print_exact_processes >&2
        exit 1
    fi
fi

echo "Building $APP_DIR"
"$ROOT_DIR/scripts/build_app.sh"
APP_DIR="$(CDPATH= cd -- "$APP_DIR" && pwd -P)"
EXECUTABLE="$APP_DIR/Contents/MacOS/MacMouseMapper"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Build did not produce executable: $EXECUTABLE" >&2
    exit 1
fi

# PlistBuddy reads the values from the bundle that will actually be launched.
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"

before_launch_pids="$(exact_pids)"
echo "Launching new process from $EXECUTABLE"
/usr/bin/open -n "$APP_DIR"

new_pid=""
for ((attempt = 0; attempt < LAUNCH_ATTEMPTS; attempt++)); do
    current_pids="$(exact_pids)"
    for pid in $current_pids; do
        if pid_in_list "$before_launch_pids" "$pid"; then
            continue
        fi
        observed_executable="$(process_executable_path "$pid")"
        if paths_match "$EXECUTABLE" "$observed_executable"; then
            new_pid="$pid"
            break 2
        fi
    done
    sleep "$POLL_INTERVAL"
done

if [[ -z "$new_pid" ]]; then
    echo "The rebuilt app did not start a new exact MacMouseMapper process from:" >&2
    echo "  $EXECUTABLE" >&2
    print_exact_processes >&2
    exit 1
fi

if pid_in_list "$before_launch_pids" "$new_pid"; then
    echo "Launch identity check failed: pid $new_pid existed before launch." >&2
    exit 1
fi

observed_executable="$(process_executable_path "$new_pid")"
if ! paths_match "$EXECUTABLE" "$observed_executable"; then
    echo "Launch identity check failed for pid $new_pid." >&2
    echo "Expected: $EXECUTABLE" >&2
    echo "Observed: $observed_executable" >&2
    exit 1
fi

# A normal open request exercises applicationShouldHandleReopen and brings the
# settings window forward without creating another process.
/usr/bin/open "$APP_DIR"
sleep 1
if ! kill -0 "$new_pid" 2>/dev/null; then
    echo "MacMouseMapper exited before the reopen check completed (pid $new_pid)." >&2
    exit 1
fi

observed_executable="$(process_executable_path "$new_pid")"
if ! paths_match "$EXECUTABLE" "$observed_executable"; then
    echo "Executable changed during reopen check for pid $new_pid." >&2
    echo "Expected: $EXECUTABLE" >&2
    echo "Observed: $observed_executable" >&2
    exit 1
fi

echo "MacMouseMapper launched, reopened settings, and remains alive."
echo "  PID: $new_pid"
echo "  Executable: $observed_executable"
echo "  Version: $APP_VERSION ($APP_BUILD)"
SIGNING_MODE="$(/usr/libexec/PlistBuddy -c 'Print :MMMCodeSigningMode' "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo unknown)"
SIGNING_IDENTITY="$(/usr/libexec/PlistBuddy -c 'Print :MMMCodeSigningIdentity' "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo unknown)"
echo "  Signing: $SIGNING_MODE ($SIGNING_IDENTITY)"
/usr/bin/codesign -d -r- "$APP_DIR" 2>&1 | /usr/bin/grep '# designated' || true
