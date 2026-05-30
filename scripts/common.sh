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

# Ensure a multi-arch capable buildx builder exists.
# Builder name must use --name; the optional positional arg is a Docker
# context/endpoint (not the builder name).
ensure_buildx_builder() {
    local builder="${1:-intellect-builder}"

    if ! docker buildx version >/dev/null 2>&1; then
        log_error "Docker Buildx is required for multi-arch builds."
        log_error "Verify with: docker buildx version"
        log_error "Install: https://docs.docker.com/build/buildx/install/"
        exit 1
    fi

    if docker buildx inspect "$builder" >/dev/null 2>&1; then
        docker buildx use "$builder"
        docker buildx inspect "$builder" --bootstrap >/dev/null 2>&1 || true
        return 0
    fi

    log_step "Creating buildx builder '${builder}'..."
    if docker buildx create \
        --name "$builder" \
        --driver docker-container \
        --use \
        --bootstrap; then
        return 0
    fi

    log_warn "Named buildx create failed; retrying with auto-generated builder name..."
    if docker buildx create \
        --driver docker-container \
        --use \
        --bootstrap; then
        return 0
    fi

    log_error "Failed to create buildx builder '${builder}'."
    log_error "Try: docker buildx create --name ${builder} --driver docker-container --use --bootstrap"
    exit 1
}

# Create a clean dist directory for a given platform/arch (wipes any prior contents).
prepare_dist() {
    local target="$1"  # e.g. darwin-arm64
    local dir="${DIST_DIR}/${target}"
    rm -rf "$dir"
    mkdir -p "${dir}/bin" "${dir}/webui"
    echo "$dir"
}

# Refuse to tar a dist tree that contains user runtime state (~/.intellect layout).
# Build scripts never copy these paths; this catches manual pollution or symlink leaks.
assert_dist_safe_for_release() {
    local dir="$1"
    local hits
    hits=$(find "$dir" \
        \( -name '.intellect' \
           -o -name 'auth.json' \
           -o -name 'config.yaml' \
           -o -name '.env' \
           -o -path '*/sessions/*' \
           -o -path '*/memories/*' \
           -o -path '*/hooks/*' \) \
        2>/dev/null | head -20 || true)
    if [[ -n "$hits" ]]; then
        log_error "Refusing to package ${dir}: found user runtime state (must not ship in releases):"
        while IFS= read -r line; do
            [[ -n "$line" ]] && log_error "  ${line}"
        done <<< "$hits"
        exit 1
    fi
}

# Collect native release tarballs for a given version (excludes helm/k8s leftovers).
collect_native_tarballs() {
    local version="$1"
    local tarball
    shopt -s nullglob
    for tarball in "${DIST_DIR}"/intellect-dist-*-"${version}".tar.gz; do
        echo "$tarball"
    done
    shopt -u nullglob
}

# Banner
banner() {
    echo "============================================================================"
    echo "  Intellect Unified Build — $*"
    echo "============================================================================"
    echo ""
}
