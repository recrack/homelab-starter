#!/bin/zsh
# Install and load the container-reclaim LaunchAgent for the current user.

set -euo pipefail
umask 077

MODULE_DIR="${0:A:h:h}"
AGENT_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/Library/Logs"
TEMPLATE="${MODULE_DIR}/launchd/container-reclaim.plist"
SCRIPT="${MODULE_DIR}/scripts/container-reclaim.sh"
LABEL=com.homelab.starter.container-reclaim
PLIST="${AGENT_DIR}/${LABEL}.plist"
USER_ID="$(/usr/bin/id -u)"

[[ -r "$TEMPLATE" ]] || {
    print -u2 -- "Missing plist template: ${TEMPLATE}"
    exit 1
}
[[ -x "$SCRIPT" ]] || {
    print -u2 -- "Module command is not executable: ${SCRIPT}"
    exit 1
}
if [[ -L "$PLIST" ]]; then
    print -u2 -- "Refusing symlinked LaunchAgent: ${PLIST}"
    exit 1
fi

/bin/mkdir -p "$AGENT_DIR" "$LOG_DIR"

/usr/bin/sed \
    -e "s|__SCRIPT__|${SCRIPT}|g" \
    -e "s|__LOG_DIR__|${LOG_DIR}|g" \
    "$TEMPLATE" > "$PLIST"

/usr/bin/plutil -lint "$PLIST" >/dev/null

/bin/launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
/bin/launchctl bootstrap "gui/${USER_ID}" "$PLIST"

print -- "Installed ${LABEL}"
print -- "  schedule : daily at 04:30"
print -- "  logs     : ${LOG_DIR}/container-reclaim.log"
print -- ""
print -- "Run 'container-reclaim.sh doctor' to verify the host is not already wedged."
