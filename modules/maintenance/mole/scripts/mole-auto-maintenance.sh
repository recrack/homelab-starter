#!/bin/zsh
# Run a non-interactive Mole maintenance action from launchd.
#
# The wrapper keeps cleanup and update jobs in the same mutually-exclusive
# lock, so a delayed launchd wake-up cannot overlap them.

set -euo pipefail

umask 077

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if [[ -z "${HOME:-}" ]]; then
    print -u2 -- "HOME is required"
    exit 78
fi
export HOME
export LANG=C
export LC_ALL=C
export NONINTERACTIVE=1
export HOMEBREW_NO_ENV_HINTS=1

typeset -r STATE_DIR="${HOME}/Library/Application Support/MoleAutoMaintenance"
typeset -r LOG_DIR="${HOME}/Library/Logs/mole-auto-maintenance"
typeset -r LOCK_DIR="${STATE_DIR}/run.lock"
typeset -r STALE_LOCK_SECONDS="${MOLE_AUTO_STALE_LOCK_SECONDS:-21600}"
typeset -r LOCK_WAIT_SECONDS="${MOLE_AUTO_LOCK_WAIT_SECONDS:-3600}"
typeset -r LOCK_POLL_SECONDS="${MOLE_AUTO_LOCK_POLL_SECONDS:-30}"

usage() {
    print -u2 -- "Usage: $0 {clean|update}"
    exit 64
}

action="${1:-}"
case "$action" in
    clean|update) ;;
    *) usage ;;
esac

timestamp() {
    /bin/date -u '+%Y-%m-%dT%H:%M:%SZ'
}

/bin/mkdir -p "$STATE_DIR" 2>/dev/null || {
    print -u2 -- "[$(timestamp)] ERROR state directory unavailable"
    exit 1
}

logging_enabled=false
if /bin/mkdir -p "$STATE_DIR" 2>/dev/null &&
    /bin/mkdir -p "$LOG_DIR" 2>/dev/null; then
    log_file="${LOG_DIR}/${action}.log"
    if exec >> "$log_file" 2>&1; then
        logging_enabled=true
    fi
fi

if [[ "$logging_enabled" != "true" ]]; then
    print -u2 -- "[$(timestamp)] WARNING log file unavailable; continuing without file logging"
fi

print -- "[$(timestamp)] START action=${action}"

acquire_lock() {
    local waited=0
    local lock_mtime=""
    local now=""
    local lock_age=0

    while true; do
        if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
            return 0
        fi

        if [[ ! -d "$LOCK_DIR" ]]; then
            print -- "[$(timestamp)] ERROR could not create lock"
            return 1
        fi

        if (( waited == 0 )); then
            print -- "[$(timestamp)] WAIT another Mole action is running"
        fi

        lock_mtime="$(/usr/bin/stat -f '%m' "$LOCK_DIR" 2>/dev/null || print 0)"
        now="$(/bin/date '+%s')"
        if [[ "$lock_mtime" == <-> && "$now" == <-> ]]; then
            lock_age=$((now - lock_mtime))
            if (( lock_age > STALE_LOCK_SECONDS )); then
                print -- "[$(timestamp)] Removing stale lock age=${lock_age}s"
                /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
                continue
            fi
        fi

        if (( waited >= LOCK_WAIT_SECONDS )); then
            print -- "[$(timestamp)] SKIP lock still exists after ${waited}s"
            return 2
        fi

        /bin/sleep "$LOCK_POLL_SECONDS"
        waited=$((waited + LOCK_POLL_SECONDS))
    done
}

lock_result=0
acquire_lock || lock_result=$?
if (( lock_result == 2 )); then
    exit 0
elif (( lock_result != 0 )); then
    exit "$lock_result"
fi

cleanup_lock() {
    if [[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
        /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
}
trap cleanup_lock EXIT INT TERM

MOLE_BIN="${MOLE_AUTO_MOLE_BIN:-}"
if [[ -n "$MOLE_BIN" && ! -x "$MOLE_BIN" ]]; then
    print -u2 -- "[$(timestamp)] ERROR configured MOLE_AUTO_MOLE_BIN is not executable: ${MOLE_BIN}"
    exit 127
fi
if [[ -z "$MOLE_BIN" && -x /opt/homebrew/bin/mo ]]; then
    MOLE_BIN=/opt/homebrew/bin/mo
elif [[ -z "$MOLE_BIN" && -x /usr/local/bin/mo ]]; then
    MOLE_BIN=/usr/local/bin/mo
fi

if [[ -z "$MOLE_BIN" ]]; then
    print -u2 -- "[$(timestamp)] ERROR mo executable not found"
    exit 127
fi

print -- "[$(timestamp)] RUN ${MOLE_BIN} ${action}"
exit_code=0
"$MOLE_BIN" "$action" || exit_code=$?
print -- "[$(timestamp)] END action=${action} status=${exit_code}"
exit "$exit_code"
