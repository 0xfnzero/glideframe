#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"

swift build --package-path "$REPO_ROOT" -c release --product GlideFrameCaptureBridge
BIN_DIR="$(swift build --package-path "$REPO_ROOT" -c release --show-bin-path)"

mkdir -p "$APP_DIR/src-tauri/binaries"
cp "$BIN_DIR/libGlideFrameCaptureBridge.dylib" "$APP_DIR/src-tauri/binaries/libGlideFrameCaptureBridge.dylib"
