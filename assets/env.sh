#!/usr/bin/env bash
# =============================================================================
# env.sh — Environment variable loader for Intellect native distribution
# =============================================================================
# Source this script before running the binaries to load configuration.
#
# Usage:
#   source ./env.sh && ./bin/intellect-webui
#   source ./env.sh && ./bin/intellect chat
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Static file path ──────────────────────────────────────────────────
export INTELLECT_WEBUI_STATIC_DIR="${INTELLECT_WEBUI_STATIC_DIR:-${SCRIPT_DIR}/webui}"

# ── State directory ───────────────────────────────────────────────────
export INTELLECT_WEBUI_STATE_DIR="${INTELLECT_WEBUI_STATE_DIR:-${HOME}/.intellect/webui}"

# ── Add binaries to PATH ──────────────────────────────────────────────
export PATH="${SCRIPT_DIR}/bin:${PATH}"

# ── Load .env files (distribution → user home) ────────────────────────
_load_env() {
    local f="$1"
    if [[ -f "$f" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$f"
        set +a
    fi
}

_load_env "${SCRIPT_DIR}/.env"
_load_env "${HOME}/.intellect/.env"

# ── Defaults ──────────────────────────────────────────────────────────
export INTELLECT_WEBUI_HOST="${INTELLECT_WEBUI_HOST:-127.0.0.1}"
export INTELLECT_WEBUI_PORT="${INTELLECT_WEBUI_PORT:-9119}"
