#!/usr/bin/env bash
# =============================================================================
# build-macos.sh — macOS native distribution build
# =============================================================================
# Compiles intellect-agent and intellect-webui into standalone native binaries
# using Nuitka. Must be run on macOS. Cannot cross-compile between Intel and
# Apple Silicon.
#
# Usage:
#   ./scripts/build-macos.sh --arch arm64 --version v1.0.0
#   ./scripts/build-macos.sh --arch amd64 --version v1.0.0
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MODE="onefile"
TARGET_ARCH=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)     TARGET_ARCH="$2"; shift 2 ;;
        --version)  VERSION="$2"; shift 2 ;;
        --mode)     MODE="$2"; shift 2 ;;
        --help|-h)  sed -n '2,14p' "$0"; exit 0 ;;
        *)          log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$TARGET_ARCH" ]]; then
    TARGET_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
fi

HOST="$(detect_host)"
HOST_OS="${HOST%%-*}"
HOST_ARCH="${HOST##*-}"

if [[ "$HOST_OS" != "darwin" ]]; then
    log_error "macOS build must run on macOS (current: $HOST_OS)"
    exit 1
fi

if [[ "$TARGET_ARCH" != "$HOST_ARCH" ]]; then
    log_error "Cannot cross-compile macOS binaries. Target arch ($TARGET_ARCH) != host ($HOST_ARCH)."
    log_error "Run this script on a $TARGET_ARCH Mac."
    exit 1
fi

VERSION="${VERSION:-$(get_version)}"
TARGET="darwin-${TARGET_ARCH}"
DIST_DIR="$(prepare_dist "$TARGET")"

banner "macOS Native Build — $TARGET ($MODE)"

# Pre-flight
log_step "Pre-flight checks..."
require_cmd python3 uv cc
log_info "Python: $(python3 --version)"
log_info "Arch: $TARGET_ARCH"

# ── Build intellect-agent ─────────────────────────────────────────────
log_step "Building intellect-agent binaries..."
cd "$AGENT_REPO"

export INTELLECT_BUILD_OUTPUT="${DIST_DIR}/bin"

if [[ -f scripts/build_binary.sh ]]; then
    bash scripts/build_binary.sh --onefile --all
else
    log_error "intellect-agent build script not found at $AGENT_REPO/scripts/build_binary.sh"
    exit 1
fi

# Move binaries to bin/ if they ended up elsewhere
for bin_name in intellect intellect-agent intellect-acp; do
    if [[ -f "${DIST_DIR}/bin/${bin_name}" ]]; then
        log_info "  [OK] ${bin_name} ($(du -h "${DIST_DIR}/bin/${bin_name}" | cut -f1))"
    else
        # Search for the binary
        found=$(find "${DIST_DIR}" -name "${bin_name}" -type f -perm +111 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            cp "$found" "${DIST_DIR}/bin/${bin_name}"
            log_info "  [OK] ${bin_name} ($(du -h "${DIST_DIR}/bin/${bin_name}" | cut -f1))"
        else
            log_error "  [MISSING] ${bin_name} — agent build failed; aborting before packaging a broken artifact"
            exit 1
        fi
    fi
done

# ── Build intellect-webui ─────────────────────────────────────────────
log_step "Building intellect-webui binary..."
cd "$WEBUI_REPO"

export INTELLECT_WEBUI_STATIC_DIR="webui"
export INTELLECT_WEBUI_OUTPUT="${DIST_DIR}/bin"

if [[ -f build.sh ]]; then
    bash build.sh --onefile
else
    log_error "intellect-webui build script not found at $WEBUI_REPO/build.sh"
    exit 1
fi

if [[ -f "${DIST_DIR}/bin/intellect-webui-darwin-${TARGET_ARCH}" ]]; then
    mv "${DIST_DIR}/bin/intellect-webui-darwin-${TARGET_ARCH}" "${DIST_DIR}/bin/intellect-webui"
fi

if [[ -f "${DIST_DIR}/bin/intellect-webui" ]]; then
    log_info "  [OK] intellect-webui ($(du -h "${DIST_DIR}/bin/intellect-webui" | cut -f1))"
else
    log_error "intellect-webui build failed"
    exit 1
fi

# ── Extract static files ──────────────────────────────────────────────
log_step "Copying webui static files..."
cp -r "${WEBUI_REPO}/static/"* "${DIST_DIR}/webui/"
# Drop patch-reject leftovers (*.rej/*.orig) so they never reach a release.
find "${DIST_DIR}/webui" -type f \( -name '*.rej' -o -name '*.orig' \) -delete
log_info "  [OK] webui/ ($(find "${DIST_DIR}/webui" -type f | wc -l | tr -d ' ') files)"

# ── Copy assets ───────────────────────────────────────────────────────
log_step "Copying distribution assets..."
cp "${INTELLECT_ROOT}/assets/ctl.sh" "${DIST_DIR}/"
cp "${INTELLECT_ROOT}/assets/env.sh" "${DIST_DIR}/"
chmod +x "${DIST_DIR}/ctl.sh" "${DIST_DIR}/env.sh"

# Ship the configuration template the README/env.sh expect (`cp .env.example .env`).
if [[ -f "${AGENT_REPO}/.env.example" ]]; then
    cp "${AGENT_REPO}/.env.example" "${DIST_DIR}/.env.example"
elif [[ -f "${INTELLECT_ROOT}/assets/.env.example" ]]; then
    cp "${INTELLECT_ROOT}/assets/.env.example" "${DIST_DIR}/.env.example"
else
    log_error "No .env.example found (looked in agent repo and assets/); aborting"
    exit 1
fi

# Generate README
sed -e "s/{{VERSION}}/${VERSION}/g" \
    -e "s/{{PLATFORM}}/macOS/g" \
    -e "s/{{ARCH}}/${TARGET_ARCH}/g" \
    -e "s/{{REQUIREMENTS}}/macOS 12+ (Apple Silicon or Intel). No Python installation required (binaries are self-contained)./g" \
    "${INTELLECT_ROOT}/assets/README.dist.md" > "${DIST_DIR}/README.md"

log_info "  [OK] ctl.sh, env.sh, .env.example, README.md"

# ── Final gate: never package a distribution missing executables ──────
for b in intellect intellect-agent intellect-acp intellect-webui; do
    if [[ ! -x "${DIST_DIR}/bin/${b}" ]]; then
        log_error "Refusing to package: bin/${b} missing or not executable"
        exit 1
    fi
done

# ── Package ────────────────────────────────────────────────────────────
log_step "Packaging..."
cd "${DIST_DIR}/.."
PKG_NAME="intellect-dist-${TARGET}-${VERSION}"
tar -czf "${PKG_NAME}.tar.gz" "$(basename "$DIST_DIR")"
mv "${PKG_NAME}.tar.gz" "${DIST_DIR}/../"

log_info ""
log_info "=== macOS Build Complete ==="
log_info "  Target:  ${TARGET}"
log_info "  Package: ${DIST_DIR}/../${PKG_NAME}.tar.gz"
log_info "  Size:    $(du -h "${DIST_DIR}/../${PKG_NAME}.tar.gz" | cut -f1)"
log_info ""
