#!/usr/bin/env bash
# =============================================================================
# ctl.sh — Intellect WebUI process manager (native distribution)
# =============================================================================
# Manages the intellect-webui native binary as a background daemon.
# Adapted from intellect-webui/ctl.sh for use with Nuitka-compiled binaries.
#
# Usage:
#   ./ctl.sh start                    Start webui daemon
#   ./ctl.sh stop                     Stop webui daemon
#   ./ctl.sh restart                  Restart webui daemon
#   ./ctl.sh status                   Show daemon status
#   ./ctl.sh logs [--lines N] [-f]    Show daemon logs
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_BIN="${SCRIPT_DIR}/bin/intellect-webui"
WEBUI_DIR="${SCRIPT_DIR}/webui"
INTELLECT_HOME="${INTELLECT_HOME:-${HOME}/.intellect}"
STATE_DIR="${INTELLECT_WEBUI_STATE_DIR:-${INTELLECT_HOME}/webui}"
PID_FILE="${INTELLECT_WEBUI_PID_FILE:-${STATE_DIR}/webui.pid}"
LOG_FILE="${INTELLECT_WEBUI_LOG_FILE:-${STATE_DIR}/webui.log}"
DEFAULT_HOST="${INTELLECT_WEBUI_HOST:-127.0.0.1}"
DEFAULT_PORT="${INTELLECT_WEBUI_PORT:-9119}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    cat <<'EOF'
Usage: ./ctl.sh <command> [args]

Commands:
  start [--host HOST] [PORT]    Start Intellect WebUI as a background daemon
  stop                          Stop the daemon
  restart [args...]             Stop, then start again
  status                        Show daemon status and health
  logs [--lines N] [-f]         Show daemon logs
EOF
}

ensure_dirs() {
    mkdir -p "${INTELLECT_HOME}" "${STATE_DIR}"
}

_pid_from_file() {
    [[ -f "${PID_FILE}" ]] || return 1
    local pid
    pid="$(tr -d '[:space:]' < "${PID_FILE}")"
    [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${pid}"
}

_is_alive() {
    local pid="$1"
    kill -0 "${pid}" >/dev/null 2>&1
}

_current_pid() {
    local pid
    pid="$(_pid_from_file)" || return 1
    if _is_alive "${pid}"; then
        printf '%s\n' "${pid}"
        return 0
    fi
    return 1
}

_clear_stale() {
    if [[ -f "${PID_FILE}" ]]; then
        rm -f "${PID_FILE}"
    fi
}

start_cmd() {
    ensure_dirs

    local host="${DEFAULT_HOST}" port="${DEFAULT_PORT}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)     host="$2"; shift 2 ;;
            --host=*)   host="${1#--host=}"; shift ;;
            --*)        shift ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then port="$1"; fi
                shift
                ;;
        esac
    done

    local existing_pid
    if existing_pid="$(_current_pid 2>/dev/null)"; then
        echo "[ctl] Intellect WebUI is already running (PID ${existing_pid})"
        return 0
    fi
    _clear_stale

    if [[ ! -f "${WEBUI_BIN}" ]]; then
        echo "[ctl] ERROR: intellect-webui binary not found at ${WEBUI_BIN}" >&2
        return 1
    fi

    export INTELLECT_WEBUI_STATIC_DIR="${INTELLECT_WEBUI_STATIC_DIR:-${WEBUI_DIR}}"
    export INTELLECT_WEBUI_STATE_DIR="${STATE_DIR}"
    export INTELLECT_WEBUI_HOST="${host}"
    export INTELLECT_WEBUI_PORT="${port}"

    : >> "${LOG_FILE}"
    (
        cd "${SCRIPT_DIR}"
        trap '' HUP
        exec nohup "${WEBUI_BIN}" >> "${LOG_FILE}" 2>&1
    ) &
    local pid=$!

    printf '%s\n' "${pid}" > "${PID_FILE}"
    sleep 0.2
    if ! _is_alive "${pid}"; then
        echo "[ctl] Intellect WebUI failed to start. Log: ${LOG_FILE}" >&2
        rm -f "${PID_FILE}"
        return 1
    fi
    echo "[ctl] Started Intellect WebUI (PID ${pid})"
    echo "[ctl] Bound: ${host}:${port}"
    echo "[ctl] Log: ${LOG_FILE}"
}

stop_cmd() {
    ensure_dirs
    local pid
    if ! pid="$(_pid_from_file 2>/dev/null)"; then
        echo "[ctl] Intellect WebUI is stopped"
        _clear_stale
        return 0
    fi

    if ! _is_alive "${pid}"; then
        _clear_stale
        return 0
    fi

    echo "[ctl] Stopping Intellect WebUI (PID ${pid})"
    kill "${pid}" >/dev/null 2>&1 || true
    local i
    for i in {1..50}; do
        if ! _is_alive "${pid}"; then
            rm -f "${PID_FILE}"
            echo "[ctl] Stopped"
            return 0
        fi
        sleep 0.1
    done

    echo "[ctl] Sending SIGKILL to PID ${pid}" >&2
    kill -KILL "${pid}" >/dev/null 2>&1 || true
    rm -f "${PID_FILE}"
}

status_cmd() {
    ensure_dirs
    local host="${DEFAULT_HOST}" port="${DEFAULT_PORT}" pid

    if pid="$(_current_pid 2>/dev/null)"; then
        local uptime health
        uptime="$(ps -p "${pid}" -o etime= 2>/dev/null | sed 's/^ *//' || true)"
        if command -v curl &>/dev/null; then
            health="$(curl -fsS --max-time 2 "http://${host}:${port}/health" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status","ok"))' 2>/dev/null || echo "unreachable")"
        else
            health="(curl not available)"
        fi
        echo -e "${GREEN}●${NC} intellect-webui — running"
        echo "  PID:     ${pid}"
        echo "  Uptime:  ${uptime:-unknown}"
        echo "  Bound:   ${host}:${port}"
        echo "  Log:     ${LOG_FILE}"
        echo "  Health:  ${health}"
    else
        _clear_stale
        echo -e "${RED}●${NC} intellect-webui — stopped"
        echo "  Bound:   ${host}:${port}"
    fi
}

logs_cmd() {
    ensure_dirs
    local lines=100 follow=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lines)    shift; lines="$1" ;;
            --lines=*)  lines="${1#--lines=}" ;;
            -f|--follow) follow=1 ;;
            --no-follow) follow=0 ;;
            *)          echo "[ctl] Unknown option: $1" >&2; return 2 ;;
        esac
        shift
    done
    [[ ! "${lines}" =~ ^[0-9]+$ ]] && lines=100
    touch "${LOG_FILE}"
    if (( follow )); then
        tail -n "${lines}" -f "${LOG_FILE}"
    else
        tail -n "${lines}" "${LOG_FILE}"
    fi
}

cmd="${1:-}"
shift 2>/dev/null || true

case "${cmd}" in
    start)    start_cmd "$@" ;;
    stop)     stop_cmd ;;
    restart)  stop_cmd; start_cmd "$@" ;;
    status)   status_cmd ;;
    logs)     logs_cmd "$@" ;;
    -h|--help|help|"") usage ;;
    *)        echo "[ctl] Unknown command: ${cmd}" >&2; usage >&2; exit 2 ;;
esac
