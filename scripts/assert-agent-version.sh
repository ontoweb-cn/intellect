#!/usr/bin/env bash
# =============================================================================
# assert-agent-version.sh — verify intellect-agent version fields before release
# =============================================================================
# Ensures intellect_cli/__init__.py and pyproject.toml agree. When --expected
# is an exact semver tag (vX.Y.Z), also checks both match that release version.
#
# Usage:
#   ./scripts/assert-agent-version.sh
#   ./scripts/assert-agent-version.sh --expected v1.2.3
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

EXPECTED=""
AGENT_REPO="${AGENT_REPO:-${INTELLECT_ROOT}/../intellect-agent}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --expected) EXPECTED="$2"; shift 2 ;;
        --agent-repo) AGENT_REPO="$2"; shift 2 ;;
        --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -d "$AGENT_REPO" ]]; then
    log_error "intellect-agent not found at ${AGENT_REPO}"
    exit 1
fi

INIT_FILE="${AGENT_REPO}/intellect_cli/__init__.py"
PYPROJECT="${AGENT_REPO}/pyproject.toml"

[[ -f "$INIT_FILE" ]] || { log_error "Missing ${INIT_FILE}"; exit 1; }
[[ -f "$PYPROJECT" ]] || { log_error "Missing ${PYPROJECT}"; exit 1; }

read_init_version() {
    python3 - "$INIT_FILE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'__version__\s*=\s*"([^"]+)"', text)
if not m:
    sys.exit("Could not parse __version__ from intellect_cli/__init__.py")
print(m.group(1))
PY
}

read_pyproject_version() {
    python3 - "$PYPROJECT" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)
if not m:
    sys.exit("Could not parse version from pyproject.toml")
print(m.group(1))
PY
}

INIT_VER="$(read_init_version)"
PY_VER="$(read_pyproject_version)"

log_info "intellect-agent __init__.py: ${INIT_VER}"
log_info "intellect-agent pyproject.toml: ${PY_VER}"

if [[ "$INIT_VER" != "$PY_VER" ]]; then
    log_error "Version mismatch: __init__.py (${INIT_VER}) != pyproject.toml (${PY_VER})"
    log_error "Run intellect-agent/scripts/release.py to bump both before releasing."
    exit 1
fi

if [[ -n "$EXPECTED" ]]; then
    norm_expected="${EXPECTED#v}"
    if [[ "$norm_expected" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ "$INIT_VER" != "$norm_expected" ]]; then
            log_error "Release tag ${EXPECTED} does not match agent versions (${INIT_VER})"
            exit 1
        fi
        log_info "[OK] Release tag ${EXPECTED} matches agent semver"
    else
        log_warn "Expected version '${EXPECTED}' is not an exact semver tag — skipping tag match"
        log_warn "(git describe tags like v1.0.0-5-gabc123 are OK; only __init__/pyproject must agree)"
    fi
fi

log_info "[OK] Agent version fields are coherent (${INIT_VER})"
