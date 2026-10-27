#!/usr/bin/env bash
set -euo pipefail
APP_PATH="$1"
# Keep application identity stable across local rebuilds, including nested code.
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_OPTIONS=(--options runtime)
# Ad-hoc developer builds have no Team ID for library validation.
if [[ "$SIGNING_IDENTITY" == "-" ]]; then SIGNING_OPTIONS=(--options 0); fi
while IFS= read -r -d '' framework; do
  codesign --force "${SIGNING_OPTIONS[@]}" --sign "$SIGNING_IDENTITY" "$framework"
done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 2>/dev/null)
codesign --force "${SIGNING_OPTIONS[@]}" --entitlements macos/GlideFrame.entitlements --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
