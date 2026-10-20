#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Pileus"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
BUNDLE_ID="${BUNDLE_ID:-com.languel.pileus}"

echo "Building ${APP_NAME} in release mode..."
swift build -c release

echo "Creating macOS application bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy application icon
if [ -f "Resources/Pileus.icns" ]; then
    cp "Resources/Pileus.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
elif [ -f "Pileus.icns" ]; then
    cp "Pileus.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

if [ -f "Resources/pileus-logo.svg" ]; then
    cp "Resources/pileus-logo.svg" "${APP_BUNDLE}/Contents/Resources/pileus-logo.svg"
fi

cat << PLIST > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 liubomir borissov (languel). All rights reserved.</string>
</dict>
</plist>
PLIST

# Determine code signing identity
DEFAULT_DEV_ID="Developer ID Application: liubomir borissov (K39T7B8529)"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"

if [ -z "$SIGNING_IDENTITY" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application: liubomir borissov (K39T7B8529)"; then
        SIGNING_IDENTITY="$DEFAULT_DEV_ID"
    elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
        SIGNING_IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')"
    else
        SIGNING_IDENTITY="-"
    fi
fi

if [ "$SIGNING_IDENTITY" = "$DEFAULT_DEV_ID" ]; then
    echo "Signing ${APP_BUNDLE} with Developer ID (${SIGNING_IDENTITY}) + Hardened Runtime..."
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "${APP_BUNDLE}"
elif [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "Signing ${APP_BUNDLE} with ${SIGNING_IDENTITY}..."
    codesign --force --deep --sign "$SIGNING_IDENTITY" "${APP_BUNDLE}"
else
    echo "Ad-hoc code signing ${APP_BUNDLE}..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "Successfully built and signed ${APP_BUNDLE}!"
