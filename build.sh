#!/bin/bash
# Builds "System Monitor.app" into ./build. Requires Xcode or the Command Line Tools
# (install with: xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/System Monitor.app"

echo "▸ Compiling (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/SystemMonitor"
if [ ! -x "$BIN" ]; then
  BIN="$(find .build -type f -perm -111 -name SystemMonitor -path '*Release*' -o -type f -perm -111 -name SystemMonitor -path '*release*' | head -n 1)"
fi
if [ -z "${BIN:-}" ] || [ ! -x "$BIN" ]; then
  echo "✗ Couldn't find the compiled SystemMonitor binary." >&2
  exit 1
fi

echo "▸ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SystemMonitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Optional custom icon: drop an AppIcon.icns into Resources/.
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Built: $(pwd)/$APP"
echo "  Run it:      open \"$APP\""
echo "  Install it:  cp -R \"$APP\" /Applications/"
