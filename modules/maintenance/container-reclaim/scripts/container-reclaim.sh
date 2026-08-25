#!/bin/zsh
# Report and reclaim sparse-image growth for Apple `container` workloads.
#
# Apple `container` backs each container with a sparse ext4 image. Blocks the
# guest frees are never returned to the host on their own, so host usage only
# grows. `fstrim` inside the guest returns them, but it must run while the
# container is idle and before the disk fills up: once the host is full,
# `container exec` itself stops responding and the fix becomes unreachable.

set -euo pipefail
umask 077

SCRIPT_DIR="${0:A:h}"
MODULE_DIR="${SCRIPT_DIR:h}"
COMMAND_NAME="${0:t}"

CONTAINER_CLI="${CONTAINER_CLI:-/usr/local/bin/container}"
CONTAINER_ROOT="${CONTAINER_ROOT:-${HOME}/Library/Application Support/com.apple.container}"
USAGE_TOOL="${SCRIPT_DIR}/ext4-usage.py"

# `container exec` blocks indefinitely when the host volume is full, so every
# call is bounded. Without this the maintenance job would hang, not fail.
EXEC_TIMEOUT="${EXEC_TIMEOUT:-60}"

# Warn while there is still room to act. Reclaiming needs working space.
MIN_FREE_GIB="${MIN_FREE_GIB:-5}"

usage() {
    local exit_code="${1:-64}"
    print -- "Usage:"
    print -- "  ${COMMAND_NAME} report              Show guest vs host usage per container"
    print -- "  ${COMMAND_NAME} trim [NAME ...]     fstrim idle containers (default: all running)"
    print -- "  ${COMMAND_NAME} trim --force NAME   Trim even if the container reports work in flight"
    print -- "  ${COMMAND_NAME} doctor              Check for the full-disk deadlock"
    print -- ""
    print -- "Environment:"
    print -- "  CONTAINER_CLI    Path to the container binary (default: ${CONTAINER_CLI})"
    print -- "  EXEC_TIMEOUT     Seconds before a container exec is abandoned (default: 60)"
    print -- "  MIN_FREE_GIB     Free-space floor before doctor reports a problem (default: 5)"
    exit "$exit_code"
}

log() {
    print -- "$@"
}

fail() {
    print -u2 -- "$@"
    exit 1
}

require_cli() {
    [[ -x "$CONTAINER_CLI" ]] || fail "container CLI not found or not executable: ${CONTAINER_CLI}"
}

free_gib() {
    # Available space on the volume backing the container root.
    local kb
    kb="$(/bin/df -k "$CONTAINER_ROOT" | /usr/bin/tail -1 | /usr/bin/awk '{print $4}')"
    print -- $(( kb / 1024 / 1024 ))
}

# Run a command with a hard time limit. zsh has no timeout(1) on macOS, so the
# child is supervised and killed rather than waited on forever.
run_bounded() {
    local limit="$1"
    shift

    "$@" &
    local pid=$!
    local waited=0

    while (( waited < limit )); do
        /bin/kill -0 "$pid" 2>/dev/null || break
        /bin/sleep 1
        (( waited += 1 ))
    done

    if /bin/kill -0 "$pid" 2>/dev/null; then
        /bin/kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 124
    fi

    wait "$pid"
}

running_containers() {
    "$CONTAINER_CLI" list 2>/dev/null |
        /usr/bin/awk 'NR > 1 && $0 !~ /^$/ { print $1 }'
}

cmd_report() {
    [[ -x "$USAGE_TOOL" ]] || fail "usage tool is missing: ${USAGE_TOOL}"

    local -a images
    images=("${CONTAINER_ROOT}/containers"/*/rootfs.ext4(N))

    (( ${#images} > 0 )) || fail "no container images found under ${CONTAINER_ROOT}/containers"

    log "Free space on container volume: $(free_gib) GiB"
    log ""
    /usr/bin/python3 "$USAGE_TOOL" "${images[@]}"
}

# A container is safe to trim when it reports no work in flight. The crawler
# convention is a /health endpoint listing active runs; absence of the endpoint
# is treated as unknown, not as idle.
container_is_idle() {
    local name="$1"
    local health

    health="$(run_bounded "$EXEC_TIMEOUT" \
        "$CONTAINER_CLI" exec "$name" curl -fsS http://127.0.0.1:9090/health 2>/dev/null)" || return 2

    [[ -n "$health" ]] || return 2

    print -- "$health" |
        /usr/bin/python3 -c 'import json,sys; sys.exit(0 if not json.load(sys.stdin).get("running") else 1)' 2>/dev/null
}

cmd_trim() {
    local force=0
    local -a targets

    while (( $# > 0 )); do
        case "$1" in
            --force) force=1; shift ;;
            -h|--help) usage 0 ;;
            -*) usage ;;
            *) targets+=("$1"); shift ;;
        esac
    done

    require_cli

    if (( ${#targets} == 0 )); then
        targets=(${(f)"$(running_containers)"})
    fi

    (( ${#targets} > 0 )) || { log "No running containers to trim."; return 0; }

    local failed=0
    local name

    for name in "${targets[@]}"; do
        [[ -n "$name" ]] || continue

        if (( ! force )); then
            local idle_status=0
            container_is_idle "$name" || idle_status=$?

            if (( idle_status == 1 )); then
                log "skip ${name}: work in flight"
                continue
            elif (( idle_status == 2 )); then
                log "skip ${name}: idle state unknown (no readable /health); use --force to override"
                continue
            fi
        fi

        local before
        before="$(free_gib)"

        local output
        local trim_status=0
        output="$(run_bounded "$EXEC_TIMEOUT" "$CONTAINER_CLI" exec "$name" fstrim -v / 2>&1)" \
            || trim_status=$?

        if (( trim_status == 0 )); then
            log "trimmed ${name}: free ${before} GiB -> $(free_gib) GiB"
        elif (( trim_status == 124 )); then
            log "FAILED ${name}: exec timed out after ${EXEC_TIMEOUT}s (host volume may be full)"
            failed=1
        elif [[ "$output" == *"Operation not permitted"* ]]; then
            # fstrim needs CAP_SYS_ADMIN; without it the ioctl is refused. Grant
            # the capability when creating the container to make it trimmable.
            log "skip ${name}: fstrim not permitted (container lacks CAP_SYS_ADMIN)"
        else
            log "FAILED ${name}: fstrim returned ${trim_status}: ${output}"
            failed=1
        fi
    done

    return "$failed"
}

cmd_doctor() {
    require_cli

    local problems=0
    local free
    free="$(free_gib)"

    log "Free space on container volume: ${free} GiB"

    if (( free < MIN_FREE_GIB )); then
        log "PROBLEM: below the ${MIN_FREE_GIB} GiB floor."
        log "  A full volume makes 'container exec' hang, which blocks fstrim,"
        log "  which is the only way to give the space back. Free space by other"
        log "  means first (build caches, unused images), then run 'trim'."
        problems=1
    fi

    # Probe exec responsiveness on any one running container.
    local probe
    probe="$(running_containers | /usr/bin/head -1)"

    if [[ -n "$probe" ]]; then
        if run_bounded "$EXEC_TIMEOUT" "$CONTAINER_CLI" exec "$probe" true >/dev/null 2>&1; then
            log "container exec: responsive"
        else
            log "PROBLEM: 'container exec' did not respond within ${EXEC_TIMEOUT}s (probed ${probe})."
            log "  fstrim cannot run until this clears. Two causes, in order of likelihood:"
            log "    1. A long-lived apiserver has wedged. Restart it, which does not"
            log "       touch container data:"
            log "         launchctl kickstart -k user/\$(id -u)/com.apple.container.apiserver"
            log "       Containers may need 'container start NAME' afterwards."
            log "    2. The host volume is full, so the sparse image cannot grow."
            problems=1
        fi
    else
        log "container exec: no running container to probe"
    fi

    if (( problems == 0 )); then
        log "No deadlock conditions detected."
    fi

    return "$problems"
}

main() {
    local action="${1:-report}"
    (( $# > 0 )) && shift

    case "$action" in
        report) cmd_report "$@" ;;
        trim) cmd_trim "$@" ;;
        doctor) cmd_doctor "$@" ;;
        -h|--help|help) usage 0 ;;
        *) usage ;;
    esac
}

main "$@"
