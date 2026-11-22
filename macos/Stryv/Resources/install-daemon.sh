#!/bin/sh
# Installs (or updates) the Stryv blocking daemon. The app runs this as root through
# the macOS administrator prompt: install-daemon.sh <path to StryvBlockd>
#
# Reinstalling during a block is safe: the new daemon reloads the saved block on launch,
# and the hosts entries stay in place while it restarts.
set -eu

SOURCE="$1"
LABEL="com.stryv.blockd"
DEST="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ ! -x "$SOURCE" ]; then
  echo "Daemon binary not found: $SOURCE" >&2
  exit 1
fi

if launchctl print "system/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "system/$LABEL" || true
  i=0
  while launchctl print "system/$LABEL" >/dev/null 2>&1 && [ "$i" -lt 40 ]; do
    sleep 0.25
    i=$((i + 1))
  done
fi

mkdir -p /Library/PrivilegedHelperTools
cp -f "$SOURCE" "$DEST.new"
chown root:wheel "$DEST.new"
chmod 755 "$DEST.new"
mv -f "$DEST.new" "$DEST"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>$LABEL</key>
    <true/>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

i=0
until launchctl bootstrap system "$PLIST" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 10 ]; then
    launchctl bootstrap system "$PLIST"
    exit $?
  fi
  sleep 0.5
done
