#!/usr/bin/env bash
# Build the SPM executable in release mode and wrap it into a macOS .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Claude Limits"
EXEC_NAME="ClaudeLimitsToolbar"
BUNDLE_ID="com.trevorscheer.claude-limits-toolbar"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"

echo "==> Building release binary"
# Universal (arm64+x86_64) builds require full Xcode; default to host arch otherwise.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS=(-c release --arch arm64 --arch x86_64)
else
    BUILD_ARGS=(-c release)
fi

swift build "${BUILD_ARGS[@]}"

BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$EXEC_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "Binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling .app bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXEC_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so Gatekeeper doesn't flat-out reject the bundle on first launch.
codesign --force --deep --sign - "$APP" || true

echo "==> Done: $APP"
