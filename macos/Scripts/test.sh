#!/bin/zsh
# Runs the StryvCore unit tests (no root needed: they use temporary files and fake clocks).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
xcodegen generate --quiet
# Build products live outside ~/Documents: macOS privacy protection blocks test runners there.
DERIVED="${STRYV_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Stryv-cli}"
xcodebuild -project Stryv.xcodeproj -scheme Stryv -derivedDataPath "$DERIVED" test "$@"
