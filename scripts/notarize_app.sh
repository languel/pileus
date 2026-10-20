#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Pileus"
APP_BUNDLE="${APP_NAME}.app"
ZIP_NAME="${APP_NAME}.zip"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-UPBGE_NOTARY}"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "Error: ${APP_BUNDLE} not found. Running ./scripts/build_app.sh first..."
    ./scripts/build_app.sh
fi

echo "Creating zip archive for Apple Notarization..."
rm -f "${ZIP_NAME}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"

echo "Submitting ${ZIP_NAME} to Apple Notary Service using keychain profile '${KEYCHAIN_PROFILE}'..."
xcrun notarytool submit "${ZIP_NAME}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait

echo "Stapling notarization ticket to ${APP_BUNDLE}..."
xcrun stapler staple "${APP_BUNDLE}"

echo "Verifying Gatekeeper assessment..."
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"

echo "Creating final distributable zip with stapled notarization..."
rm -f "${ZIP_NAME}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"

echo "✅ Successfully built, signed, notarized, and stapled ${APP_BUNDLE} (${ZIP_NAME})!"
