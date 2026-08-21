#!/usr/bin/env bash
# Build TGrid.app — the menu bar UI for t-GRID — from a single Swift file.
# No Xcode project, no package manager, no dependencies.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/TGrid.swift"
APP="${1:-$HOME/Applications/TGrid.app}"
BIN="$APP/Contents/MacOS/TGrid"

command -v swiftc >/dev/null || {
  echo "swiftc not found — install the Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TGrid</string>
  <key>CFBundleDisplayName</key><string>TGrid</string>
  <key>CFBundleIdentifier</key><string>io.tgrid.menubar</string>
  <key>CFBundleExecutable</key><string>TGrid</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- menu bar only: no Dock icon, no app switcher entry -->
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>t-GRID arranges your Terminal windows into a grid.</string>
</dict>
</plist>
PLIST

echo "compiling…"
swiftc -O -parse-as-library -o "$BIN" "$SRC"

# ad-hoc sign: keeps macOS's Automation permission stable across rebuilds
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
