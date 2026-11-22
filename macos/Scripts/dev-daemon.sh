#!/bin/zsh
# Runs the blocker daemon as *your user* against a fake hosts file, so you can develop and
# test the whole app without root and without touching /etc/hosts.
#
#   Scripts/dev-daemon.sh start   # build, then load the dev daemon as a LaunchAgent
#   Scripts/dev-daemon.sh app     # launch the built app pointed at the dev daemon
#   Scripts/dev-daemon.sh hosts   # show the fake hosts file
#   Scripts/dev-daemon.sh stop    # unload it and delete its files
set -euo pipefail

ROOT="${0:A:h:h}"
LABEL="com.stryv.blockd.dev"
DEV_DIR="$HOME/Library/Application Support/Stryv Dev"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DERIVED="${STRYV_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Stryv-cli}"
PRODUCTS="$DERIVED/Build/Products/Debug"

build() {
  cd "$ROOT"
  xcodegen generate --quiet
  xcodebuild -project Stryv.xcodeproj -scheme Stryv -configuration Debug -derivedDataPath "$DERIVED" build -quiet
}

case "${1:-}" in
  start)
    build
    mkdir -p "$DEV_DIR" "${PLIST:h}"
    [[ -f "$DEV_DIR/hosts" ]] || printf '127.0.0.1 localhost\n' > "$DEV_DIR/hosts"
    cp -f "$PRODUCTS/StryvBlockd" "$DEV_DIR/StryvBlockd"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEV_DIR/StryvBlockd</string></array>
  <key>MachServices</key><dict><key>$LABEL</key><true/></dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>STRYV_MACH_SERVICE</key><string>$LABEL</string>
    <key>STRYV_HOSTS_PATH</key><string>$DEV_DIR/hosts</string>
    <key>STRYV_STATE_PATH</key><string>$DEV_DIR/block-state.json</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$PLIST"
    echo "Dev daemon running. Fake hosts file: $DEV_DIR/hosts"
    ;;
  app)
    pkill -x Stryv 2>/dev/null || true
    STRYV_MACH_SERVICE="$LABEL" "$PRODUCTS/Stryv.app/Contents/MacOS/Stryv" &
    echo "Stryv (dev) launched"
    ;;
  hosts)
    cat "$DEV_DIR/hosts"
    ;;
  stop)
    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$DEV_DIR"
    echo "Dev daemon removed"
    ;;
  *)
    echo "usage: $0 start|app|hosts|stop"
    exit 1
    ;;
esac
