#!/bin/bash
# Build the menu-bar app into a no-Dock-icon agent .app bundle and install it.
# Usage:  ./build_app.sh        (build + install to /Applications)
#         ./build_app.sh --here (build only)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

echo "Building (release)…"
swift build -c release

app="$here/KeepSoundAlive.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp ".build/release/KeepAlive" "$app/Contents/MacOS/KeepSoundAlive"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>KeepSoundAlive</string>
  <key>CFBundleDisplayName</key><string>Keep Sound Alive</string>
  <key>CFBundleIdentifier</key><string>org.hersey.keepsoundalive</string>
  <key>CFBundleExecutable</key><string>KeepSoundAlive</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <!-- "Monitor audio" uses a Core Audio process tap to read the system output level
       so the keep-alive tone can mute itself over real playback. The tap needs the
       user's authorization; these strings explain the prompt. -->
  <key>NSAudioCaptureUsageDescription</key><string>Keep Sound Alive watches the audio output level so it can mute its keep-alive tone while you're playing music or video.</string>
  <key>NSMicrophoneUsageDescription</key><string>Keep Sound Alive watches the audio output level so it can mute its keep-alive tone while you're playing music or video.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity (override via SIGN_IDENTITY; empty string skips).
SIGN_IDENTITY="${SIGN_IDENTITY-Apple Development: David Hersey (CUACYBN73G)}"
if [ -n "$SIGN_IDENTITY" ]; then
  if codesign --force --deep --sign "$SIGN_IDENTITY" "$app" 2>/dev/null; then
    echo "Signed with: $SIGN_IDENTITY"
  else
    echo "WARN: codesign failed for '$SIGN_IDENTITY' — app is unsigned."
  fi
fi

echo "Built $app"

if [ "${1:-}" != "--here" ]; then
  dest="/Applications/Keep Sound Alive.app"
  killall KeepSoundAlive 2>/dev/null || true
  rm -rf "$dest"
  cp -R "$app" "$dest"
  echo "Installed → $dest"
  echo "Open now:  open \"$dest\""
fi
