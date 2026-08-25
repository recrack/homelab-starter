#!/bin/zsh
# Install and load the Mole cleanup/update LaunchAgents for the current user.

set -euo pipefail

REPO_DIR="${0:A:h:h}"
AGENT_DIR="${HOME}/Library/LaunchAgents"
INSTALL_DIR="${HOME}/Library/Application Support/MoleAutoMaintenance"
SCHEDULE_FILE="${INSTALL_DIR}/schedule.conf"
RUNNER_SOURCE="${REPO_DIR}/scripts/mole-auto-maintenance.sh"
INSTALLED_RUNNER="${INSTALL_DIR}/mole-auto-maintenance.sh"
USER_ID="$(/usr/bin/id -u)"

WEEKDAY=0
UPDATE_AT=03:00
CLEANUP_AT=04:00
CLEANUP_INTERVAL=0
LABEL_PREFIX=com.homelab.starter.mole

if [[ -L "$SCHEDULE_FILE" ]]; then
    print -u2 -- "Refusing symlinked schedule file: ${SCHEDULE_FILE}"
    exit 1
fi
if [[ -f "$SCHEDULE_FILE" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            WEEKDAY) WEEKDAY="$value" ;;
            UPDATE_AT) UPDATE_AT="$value" ;;
            CLEANUP_AT) CLEANUP_AT="$value" ;;
            CLEANUP_INTERVAL) CLEANUP_INTERVAL="$value" ;;
            LABEL_PREFIX) LABEL_PREFIX="$value" ;;
            ''|\#*) ;;
            *) print -u2 -- "Unknown schedule setting: ${key}"; exit 1 ;;
        esac
    done < "$SCHEDULE_FILE"
fi

if [[ "$WEEKDAY" == 7 ]]; then WEEKDAY=0; fi
if [[ "$WEEKDAY" != <-> ]] || (( WEEKDAY < 0 || WEEKDAY > 6 )); then
    print -u2 -- "Invalid WEEKDAY in ${SCHEDULE_FILE}: ${WEEKDAY}"
    exit 1
fi

validate_time() {
    local label="$1"
    local value="$2"
    local hour="${value%%:*}"
    local minute="${value##*:}"
    [[ "$value" =~ '^[0-9]{1,2}:[0-9]{2}$' ]] || {
        print -u2 -- "Invalid ${label} in ${SCHEDULE_FILE}: ${value}"
        exit 1
    }
    hour=$((10#$hour))
    minute=$((10#$minute))
    if (( hour > 23 || minute > 59 )); then
        print -u2 -- "Invalid ${label} in ${SCHEDULE_FILE}: ${value}"
        exit 1
    fi
}

validate_time UPDATE_AT "$UPDATE_AT"
validate_time CLEANUP_AT "$CLEANUP_AT"
if [[ "$CLEANUP_INTERVAL" != <-> ]] || (( CLEANUP_INTERVAL != 0 && CLEANUP_INTERVAL != 3600 )); then
    print -u2 -- "Invalid CLEANUP_INTERVAL in ${SCHEDULE_FILE}: ${CLEANUP_INTERVAL}"
    exit 1
fi
if [[ ! "$LABEL_PREFIX" =~ '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$' || "$LABEL_PREFIX" == *..* ]]; then
    print -u2 -- "Invalid LABEL_PREFIX in ${SCHEDULE_FILE}: ${LABEL_PREFIX}"
    exit 1
fi
UPDATE_HOUR=$((10#${UPDATE_AT%%:*}))
UPDATE_MINUTE=$((10#${UPDATE_AT##*:}))
CLEANUP_HOUR=$((10#${CLEANUP_AT%%:*}))
CLEANUP_MINUTE=$((10#${CLEANUP_AT##*:}))
UPDATE_LABEL="${LABEL_PREFIX}.update"
CLEANUP_LABEL="${LABEL_PREFIX}.cleanup"

/bin/mkdir -p "$AGENT_DIR" "$INSTALL_DIR"
/bin/mkdir -p "${HOME}/Library/Logs/mole-auto-maintenance" 2>/dev/null || true

if [[ ! -x "$RUNNER_SOURCE" ]]; then
    print -u2 -- "Runner is missing or not executable: ${RUNNER_SOURCE}"
    exit 1
fi

/bin/cp "$RUNNER_SOURCE" "$INSTALLED_RUNNER"
/bin/chmod 0755 "$INSTALLED_RUNNER"

legacy_labels=(
    com.recrack.mole-update
    com.recrack.mole-cleanup
    com.recrack.mole.update
    com.recrack.mole.cleanup
)
if [[ -n "${HOMELAB_PREVIOUS_LABEL_PREFIX:-}" &&
    "${HOMELAB_PREVIOUS_LABEL_PREFIX}" != "$LABEL_PREFIX" ]]; then
    if [[ "${HOMELAB_PREVIOUS_LABEL_PREFIX}" =~ '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$' &&
        "${HOMELAB_PREVIOUS_LABEL_PREFIX}" != *..* ]]; then
        legacy_labels+=(
            "${HOMELAB_PREVIOUS_LABEL_PREFIX}.update"
            "${HOMELAB_PREVIOUS_LABEL_PREFIX}.cleanup"
        )
    fi
fi
for legacy_label in "${legacy_labels[@]}"; do
    if [[ "$legacy_label" != "$UPDATE_LABEL" && "$legacy_label" != "$CLEANUP_LABEL" ]] &&
        /bin/launchctl print "gui/${USER_ID}/${legacy_label}" >/dev/null 2>&1; then
        /bin/launchctl bootout "gui/${USER_ID}/${legacy_label}"
    fi
    legacy_plist="${AGENT_DIR}/${legacy_label}.plist"
    if [[ "$legacy_label" != "$UPDATE_LABEL" && "$legacy_label" != "$CLEANUP_LABEL" &&
        -f "$legacy_plist" && ! -L "$legacy_plist" ]]; then
        /bin/rm -f "$legacy_plist"
    fi
done

for plist in "$REPO_DIR"/launchd/mole-update.plist \
             "$REPO_DIR"/launchd/mole-cleanup.plist; do
    template_name="$(/usr/bin/basename "$plist")"
    if [[ "$template_name" == mole-update.plist ]]; then
        label="$UPDATE_LABEL"
        template_action="update"
    else
        label="$CLEANUP_LABEL"
        template_action="clean"
    fi
    destination="${AGENT_DIR}/${label}.plist"

    /usr/bin/plutil -lint "$plist" >/dev/null
    if /bin/launchctl print "gui/${USER_ID}/${label}" >/dev/null 2>&1; then
        /bin/launchctl bootout "gui/${USER_ID}/${label}"
    fi
    /bin/cp "$plist" "$destination"
    /usr/bin/plutil -replace Label -string "$label" "$destination"
    /usr/bin/plutil -remove ProgramArguments.0 "$destination"
    /usr/bin/plutil -insert ProgramArguments.0 -string "$INSTALLED_RUNNER" "$destination"
    /usr/bin/plutil -replace EnvironmentVariables.HOME -string "$HOME" "$destination"
    /usr/bin/plutil -replace StartCalendarInterval.Weekday -integer "$WEEKDAY" "$destination"
    if [[ "$template_action" == update ]]; then
        /usr/bin/plutil -replace StartCalendarInterval.Hour -integer "$UPDATE_HOUR" "$destination"
        /usr/bin/plutil -replace StartCalendarInterval.Minute -integer "$UPDATE_MINUTE" "$destination"
    elif (( CLEANUP_INTERVAL == 3600 )); then
        /usr/bin/plutil -remove StartCalendarInterval "$destination"
        /usr/bin/plutil -insert StartInterval -integer "$CLEANUP_INTERVAL" "$destination"
    else
        if /usr/bin/plutil -type StartInterval "$destination" >/dev/null 2>&1; then
            /usr/bin/plutil -remove StartInterval "$destination"
        fi
        /usr/bin/plutil -replace StartCalendarInterval.Hour -integer "$CLEANUP_HOUR" "$destination"
        /usr/bin/plutil -replace StartCalendarInterval.Minute -integer "$CLEANUP_MINUTE" "$destination"
    fi
    /bin/chmod 0644 "$destination"
    /usr/bin/plutil -lint "$destination" >/dev/null
    /bin/launchctl bootstrap "gui/${USER_ID}" "$destination"
    print -- "Loaded ${label}"
done

print -- "Mole update: weekday=${WEEKDAY} ${UPDATE_AT}"
if (( CLEANUP_INTERVAL == 3600 )); then
    print -- "Mole cleanup: every hour"
else
    print -- "Mole cleanup: weekday=${WEEKDAY} ${CLEANUP_AT}"
fi
print -- "Logs: ${HOME}/Library/Logs/mole-auto-maintenance"
