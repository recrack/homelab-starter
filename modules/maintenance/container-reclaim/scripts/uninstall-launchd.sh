#!/bin/zsh
# Remove the container-reclaim LaunchAgent for the current user.

set -euo pipefail

AGENT_DIR="${HOME}/Library/LaunchAgents"
LABEL=com.homelab.starter.container-reclaim
PLIST="${AGENT_DIR}/${LABEL}.plist"
USER_ID="$(/usr/bin/id -u)"

/bin/launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true

if [[ -L "$PLIST" ]]; then
    print -u2 -- "Refusing to remove symlinked LaunchAgent: ${PLIST}"
    exit 1
fi

/bin/rm -f "$PLIST"

print -- "Removed ${LABEL}"
