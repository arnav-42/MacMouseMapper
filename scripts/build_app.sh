#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
APP_VERSION="1.3.0"
APP_BUILD="4"

# Prefer an existing stable identity. Never create a certificate or silently
# treat an ad-hoc signature as a persistent TCC identity.
SIGNING_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }'
)"
if [[ -n "$SIGNING_IDENTITY" ]]; then
    SIGNING_MODE="stable"
    SIGNING_IDENTITY_LABEL="$SIGNING_IDENTITY"
else
    SIGNING_MODE="adhoc"
    SIGNING_IDENTITY_LABEL="Ad-hoc (no stable signing identity available)"
fi

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    printf '%s' "$value"
}

swift build -c release --product MacMouseMapper
BIN_DIR="$(swift build -c release --product MacMouseMapper --show-bin-path)"
APP_DIR="$ROOT_DIR/build/MacMouseMapper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/MacMouseMapper" "$MACOS_DIR/MacMouseMapper"
chmod 755 "$MACOS_DIR/MacMouseMapper"

# Keep the SwiftPM resource bundle alongside the executable for Bundle.module,
# and copy the source PNGs into the main bundle for installed-app lookup.
resource_bundle=""
while IFS= read -r candidate; do
    resource_bundle="$candidate"
    break
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print)
if [[ -n "$resource_bundle" ]]; then
    cp -R "$resource_bundle" "$RESOURCES_DIR/"
fi
for image in "$ROOT_DIR"/Sources/MacMouseMapper/Resources/*.png; do
    cp "$image" "$RESOURCES_DIR/"
done

escaped_identity="$(xml_escape "$SIGNING_IDENTITY_LABEL")"
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>MacMouseMapper</string>
    <key>CFBundleExecutable</key>
    <string>MacMouseMapper</string>
    <key>CFBundleIdentifier</key>
    <string>com.macmousemapper.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacMouseMapper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>MMMCodeSigningMode</key>
    <string>$SIGNING_MODE</string>
    <key>MMMCodeSigningIdentity</key>
    <string>$escaped_identity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGNING_IDENTITY" ]]; then
    /usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR" >/dev/null
else
    /usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    echo "WARNING: no Apple Development or Developer ID identity is available; this build is ad-hoc and may receive a new TCC identity." >&2
    echo "Use Repair Access in the packaged app after a rebuild if Accessibility points at an older executable." >&2
else
    echo "Signing with stable identity: $SIGNING_IDENTITY"
fi
echo "Code-signing designated requirement:"
/usr/bin/codesign -d -r- -vvv "$APP_DIR" 2>&1 \
    | /usr/bin/grep -E 'Identifier=|Signature=|TeamIdentifier=|# designated' || true
echo "$APP_DIR"
