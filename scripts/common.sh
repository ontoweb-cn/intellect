#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared functions for Intellect build scripts
# =============================================================================
set -euo pipefail

INTELLECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_REPO="${INTELLECT_ROOT}/../intellect-agent"
WEBUI_REPO="${INTELLECT_ROOT}/../intellect-webui"
DIST_DIR="${INTELLECT_ROOT}/dist"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Detect host platform and architecture
detect_host() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)
    case "$os" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        *)      log_error "Unsupported OS: $os"; exit 1 ;;
    esac
    case "$arch" in
        arm64|aarch64) arch="arm64" ;;
        x86_64)        arch="amd64" ;;
        *)             log_error "Unsupported arch: $arch"; exit 1 ;;
    esac
    echo "${os}-${arch}"
}

# Normalize architecture names for Docker
docker_arch() {
    case "$1" in
        amd64|x86_64) echo "amd64" ;;
        arm64)        echo "arm64" ;;
        *)            echo "$1" ;;
    esac
}

# Normalize architecture names for Linux (Nuitka convention)
linux_arch() {
    case "$1" in
        amd64)  echo "x86_64" ;;
        arm64)  echo "arm64" ;;
        *)      echo "$1" ;;
    esac
}

# Get version from git or fallback
get_version() {
    local repo="${1:-${AGENT_REPO}}"
    if [ -n "${VERSION_OVERRIDE:-}" ]; then
        echo "$VERSION_OVERRIDE"
    elif git -C "$repo" describe --tags --always 2>/dev/null; then
        :
    else
        echo "dev"
    fi
}

# Check required commands
require_cmd() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "'$cmd' not found. Please install it first."
            exit 1
        fi
    done
}

# Create dist directory for a given platform/arch
prepare_dist() {
    local target="$1"  # e.g. darwin-arm64
    local dir="${DIST_DIR}/${target}"
    mkdir -p "${dir}/bin" "${dir}/webui"
    echo "$dir"
}

# Banner
banner() {
    echo "============================================================================"
    echo "  Intellect Unified Build — $*"
    echo "============================================================================"
    echo ""
}
