#!/bin/zsh
# Unload and remove the Mole cleanup/update LaunchAgents installed by this repo.

set -euo pipefail

AGENT_DIR="${HOME}/Library/LaunchAgents"
SCHEDULE_FILE="${HOME}/Library/Application Support/MoleAutoMaintenance/schedule.conf"
USER_ID="$(/usr/bin/id -u)"
LABEL_PREFIX=com.homelab.starter.mole

if [[ -L "$SCHEDULE_FILE" ]]; then
    print -u2 -- "Refusing symlinked schedule file: ${SCHEDULE_FILE}"
    exit 1
fi
if [[ -f "$SCHEDULE_FILE" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            LABEL_PREFIX) LABEL_PREFIX="$value" ;;
            ''|\#*) ;;
            *) ;;
        esac
    done < "$SCHEDULE_FILE"
fi

if [[ ! "$LABEL_PREFIX" =~ '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$' || "$LABEL_PREFIX" == *..* ]]; then
    print -u2 -- "Invalid LABEL_PREFIX in ${SCHEDULE_FILE}: ${LABEL_PREFIX}"
    exit 1
fi

labels=(
    "${LABEL_PREFIX}.update"
    "${LABEL_PREFIX}.cleanup"
    com.recrack.mole-update
    com.recrack.mole-cleanup
    com.recrack.mole.update
    com.recrack.mole.cleanup
)
for label in "${labels[@]}"; do
    if /bin/launchctl print "gui/${USER_ID}/${label}" >/dev/null 2>&1; then
        /bin/launchctl bootout "gui/${USER_ID}/${label}"
    fi
    /bin/rm -f "${AGENT_DIR}/${label}.plist"
    print -- "Removed ${label}"
done
