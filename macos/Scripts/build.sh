#!/bin/zsh
# Builds Stryv.app into macos/build/. Pass --install to copy it to /Applications.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

# Build products live outside ~/Documents: macOS privacy protection blocks test runners there.
DERIVED="${STRYV_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Stryv-cli}"

xcodebuild \
  -project Stryv.xcodeproj \
  -scheme Stryv \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

APP="$DERIVED/Build/Products/Release/Stryv.app"
[[ -d "$APP" ]] || { echo "Build failed: no Stryv.app"; exit 1; }

rm -rf "$ROOT/build"
mkdir -p "$ROOT/build"
cp -R "$APP" "$ROOT/build/"
codesign --verify --deep --strict "$ROOT/build/Stryv.app"
echo "Built $ROOT/build/Stryv.app"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'tell application "Stryv" to quit' >/dev/null 2>&1 || true
  # Wait for the old copy to exit, or `open` would just reactivate it while it quits.
  for _ in {1..40}; do pgrep -f "/Applications/Stryv.app/Contents/MacOS/Stryv" >/dev/null || break; sleep 0.25; done
  rm -rf /Applications/Stryv.app
  cp -R "$ROOT/build/Stryv.app" /Applications/
  echo "Installed /Applications/Stryv.app"
  # Launch Services can take a moment to register the replaced bundle; retry until it runs.
  for _ in {1..5}; do
    open /Applications/Stryv.app
    sleep 2
    pgrep -f "/Applications/Stryv.app/Contents/MacOS/Stryv" >/dev/null && break
  done
fi
