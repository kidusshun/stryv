#!/bin/zsh
# Removes the Stryv blocker daemon. Refuses while a block is running.
#   sudo macos/Scripts/uninstall-daemon.sh
set -euo pipefail

LABEL="com.stryv.blockd"
STATE="/Library/Application Support/Stryv/block-state.json"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo."
  exit 1
fi

if [[ -f "$STATE" ]]; then
  ENDS="$(/usr/bin/plutil -extract block.endsAt raw -o - "$STATE" 2>/dev/null || echo 0)"
  ENDS="${ENDS%.*}"
  if (( ENDS > $(date +%s) )); then
    echo "A block is running until $(date -r "$ENDS"). Uninstall after it ends."
    exit 1
  fi
fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"
rm -rf "/Library/Application Support/Stryv"
/usr/bin/sed -i '' '/^# >>> Stryv block/,/^# <<< Stryv block/d' /private/etc/hosts
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
echo "Stryv blocker removed."
