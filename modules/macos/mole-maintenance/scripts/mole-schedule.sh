#!/bin/zsh
# Friendly command for changing the Mole LaunchAgent schedule.

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
REPO_DIR="${SCRIPT_DIR:h}"
INSTALL_DIR="${HOME}/Library/Application Support/MoleAutoMaintenance"
SCHEDULE_FILE="${INSTALL_DIR}/schedule.conf"
COMMAND_NAME="${0:t}"

UPDATE_AT=03:00
CLEANUP_AT=04:00
WEEKDAY=0
LABEL_PREFIX=com.homelab.starter.mole

usage() {
    local exit_code="${1:-64}"
    print -- "Usage:"
    print -- "  ${COMMAND_NAME}                         Show current schedule"
    print -- "  ${COMMAND_NAME} --update-at HH:MM --cleanup-at HH:MM [--day DAY]"
    print -- "  ${COMMAND_NAME} --label-prefix PREFIX"
    print -- "  ${COMMAND_NAME} on                      Re-enable the saved schedule"
    print -- "  ${COMMAND_NAME} off                     Disable both jobs"
    print -- "  ${COMMAND_NAME} status                  Show current schedule and job state"
    print -- ""
    print -- "DAY: sunday|monday|...|saturday (or 0-6; 0 is Sunday)"
    exit "$exit_code"
}

load_saved_schedule() {
    [[ ! -L "$SCHEDULE_FILE" ]] || {
        print -u2 -- "Refusing symlinked schedule file: ${SCHEDULE_FILE}"
        exit 1
    }
    [[ -e "$SCHEDULE_FILE" ]] || return 0

    local key=""
    local value=""
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            UPDATE_AT) UPDATE_AT="$value" ;;
            CLEANUP_AT) CLEANUP_AT="$value" ;;
            WEEKDAY) WEEKDAY="$value" ;;
            LABEL_PREFIX) LABEL_PREFIX="$value" ;;
            ''|\#*) ;;
            *) print -u2 -- "Unknown schedule setting: ${key}"; exit 1 ;;
        esac
    done < "$SCHEDULE_FILE"
}

normalize_time() {
    local value="$1"
    local hour="${value%%:*}"
    local minute="${value##*:}"

    [[ "$value" =~ '^[0-9]{1,2}:[0-9]{2}$' ]] || {
        print -u2 -- "Invalid time '${value}'. Use HH:MM, for example 22:30."
        exit 64
    }
    hour=$((10#$hour))
    minute=$((10#$minute))
    if (( hour > 23 || minute > 59 )); then
        print -u2 -- "Invalid time '${value}'. Hours are 00-23 and minutes are 00-59."
        exit 64
    fi
    printf '%02d:%02d' "$hour" "$minute"
}

normalize_day() {
    local value="${1:l}"
    case "$value" in
        sunday|sun|0|7) printf '0' ;;
        monday|mon|1) printf '1' ;;
        tuesday|tue|2) printf '2' ;;
        wednesday|wed|3) printf '3' ;;
        thursday|thu|4) printf '4' ;;
        friday|fri|5) printf '5' ;;
        saturday|sat|6) printf '6' ;;
        *) print -u2 -- "Invalid day '${1}'. Use sunday-saturday or 0-6."; exit 64 ;;
    esac
}

normalize_label_prefix() {
    local value="$1"
    if [[ ! "$value" =~ '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$' || "$value" == *..* ]]; then
        print -u2 -- "Invalid label prefix '${value}'. Use reverse-DNS style text."
        exit 64
    fi
    printf '%s' "$value"
}

show_status() {
    load_saved_schedule
    local -a days=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
    local update_label="${LABEL_PREFIX}.update"
    local cleanup_label="${LABEL_PREFIX}.cleanup"
    print -- "Update: ${days[$((WEEKDAY + 1))]} ${UPDATE_AT}"
    print -- "Cleanup: ${days[$((WEEKDAY + 1))]} ${CLEANUP_AT}"
    for label in "$update_label" "$cleanup_label"; do
        if /bin/launchctl print "gui/$(/usr/bin/id -u)/${label}" >/dev/null 2>&1; then
            print -- "${label}: enabled"
        else
            print -- "${label}: disabled"
        fi
    done
}

load_saved_schedule
ORIGINAL_LABEL_PREFIX="$LABEL_PREFIX"

if [[ $# -eq 0 || "${1:-}" == "status" ]]; then
    [[ $# -eq 0 || $# -eq 1 ]] || usage
    show_status
    exit 0
fi

case "${1:-}" in
    on)
        [[ $# -eq 1 ]] || usage
        exec "$REPO_DIR/scripts/install-launchd.sh"
        ;;
    off)
        [[ $# -eq 1 ]] || usage
        exec "$REPO_DIR/scripts/uninstall-launchd.sh"
        ;;
    -h|--help|help)
        usage 0
        ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --update-at)
            [[ $# -ge 2 ]] || usage
            UPDATE_AT="$2"
            shift 2
            ;;
        --cleanup-at)
            [[ $# -ge 2 ]] || usage
            CLEANUP_AT="$2"
            shift 2
            ;;
        --day)
            [[ $# -ge 2 ]] || usage
            WEEKDAY="$2"
            shift 2
            ;;
        --label-prefix)
            [[ $# -ge 2 ]] || usage
            LABEL_PREFIX="$2"
            shift 2
            ;;
        -h|--help|help)
            usage 0
            ;;
        *)
            print -u2 -- "Unknown option: $1"
            usage
            ;;
    esac
done

UPDATE_AT="$(normalize_time "$UPDATE_AT")"
CLEANUP_AT="$(normalize_time "$CLEANUP_AT")"
WEEKDAY="$(normalize_day "$WEEKDAY")"
LABEL_PREFIX="$(normalize_label_prefix "$LABEL_PREFIX")"

/bin/mkdir -p "$INSTALL_DIR"
schedule_tmp="$(/usr/bin/mktemp "${INSTALL_DIR}/schedule.conf.XXXXXX")"
trap '/bin/rm -f "$schedule_tmp" 2>/dev/null || true' EXIT INT TERM
{
    print "WEEKDAY=${WEEKDAY}"
    print "UPDATE_AT=${UPDATE_AT}"
    print "CLEANUP_AT=${CLEANUP_AT}"
    print "LABEL_PREFIX=${LABEL_PREFIX}"
} > "$schedule_tmp"
/bin/mv "$schedule_tmp" "$SCHEDULE_FILE"
trap - EXIT INT TERM

if [[ "$LABEL_PREFIX" != "$ORIGINAL_LABEL_PREFIX" ]]; then
    export HOMELAB_PREVIOUS_LABEL_PREFIX="$ORIGINAL_LABEL_PREFIX"
fi
exec "$REPO_DIR/scripts/install-launchd.sh"
