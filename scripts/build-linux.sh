#!/usr/bin/env bash
# =============================================================================
# build-linux.sh — Linux native distribution build (Docker-based Nuitka)
# =============================================================================
# Builds native Linux binaries inside Docker containers, supporting both
# x86_64 and arm64 via buildx + QEMU.
#
# Usage:
#   ./scripts/build-linux.sh --arch x86_64            # amd64 only
#   ./scripts/build-linux.sh --arch arm64             # arm64 only
#   ./scripts/build-linux.sh --arch x86_64,arm64      # both
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MODE="onefile"
TARGET_ARCHS=()
VERSION=""
BUILDER_IMAGE="intellect-linux-builder"
REBUILD_BUILDER=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)       IFS=',' read -ra TARGET_ARCHS <<< "$2"; shift 2 ;;
        --version)    VERSION="$2"; shift 2 ;;
        --mode)       MODE="$2"; shift 2 ;;
        --no-cache)   REBUILD_BUILDER=true; shift ;;
        --help|-h)    sed -n '2,14p' "$0"; exit 0 ;;
        *)            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ${#TARGET_ARCHS[@]} -eq 0 ]]; then
    TARGET_ARCHS=(x86_64 arm64)
fi

VERSION="${VERSION:-$(get_version)}"

banner "Linux Native Build — ${TARGET_ARCHS[*]} ($MODE)"

# Pre-flight
log_step "Pre-flight checks..."
require_cmd docker

# Ensure buildx builder with QEMU
HOST_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
NEED_QEMU=false
for arch in "${TARGET_ARCHS[@]}"; do
    linux_a=$(linux_arch "$arch")
    if [[ "$linux_a" != "$HOST_ARCH" ]] && [[ "$HOST_ARCH" != "amd64" || "$linux_a" != "x86_64" ]]; then
        NEED_QEMU=true
    fi
done

if $NEED_QEMU; then
    if ! docker buildx inspect intellect-builder &>/dev/null; then
        log_step "Creating buildx builder (multi-arch)..."
        docker buildx create --name intellect-builder --use --bootstrap
    else
        docker buildx use intellect-builder
    fi
fi

# ── Build or reuse builder image ──────────────────────────────────────
build_builder_image() {
    local arch="$1"
    local docker_arch=$(docker_arch "$arch")
    local image_tag="${BUILDER_IMAGE}:${docker_arch}"
    local dockerfile="${INTELLECT_ROOT}/docker/Dockerfile.linux-builder"

    if ! $REBUILD_BUILDER && docker image inspect "$image_tag" &>/dev/null; then
        log_info "Builder image ${image_tag} already exists — skipping"
        return
    fi

    log_step "Building builder image for ${docker_arch}..."
    docker build \
        ${REBUILD_BUILDER:+--no-cache} \
        --platform "linux/${docker_arch}" \
        -f "$dockerfile" \
        -t "$image_tag" \
        "${INTELLECT_ROOT}/.."

    log_info "Builder image ${image_tag} ready"
}

# ── Build for a single architecture ───────────────────────────────────
build_for_arch() {
    local arch="$1"  # x86_64 or arm64
    local docker_arch=$(docker_arch "$arch")
    local target="linux-${docker_arch}"
    local dist_dir="$(prepare_dist "$target")"

    log_step "Building for linux/${docker_arch}..."

    # Build agent binaries
    log_info "Building intellect-agent..."
    docker run \
        --platform "linux/${docker_arch}" \
        --rm \
        -u "$(id -u):$(id -g)" \
        -v "${AGENT_REPO}:/build/agent:ro" \
        -v "${dist_dir}/bin:/output:rw" \
        -e OUTPUT_DIR=/output \
        -e NUITKA_MODE="${MODE}" \
        "${BUILDER_IMAGE}:${docker_arch}" \
        bash -c "
            cd /build/agent && \
            pip install nuitka cython && \
            uv sync --frozen --extra all && \
            python -m nuitka \
                --${MODE} \
                --output-dir=/output \
                --output-filename=intellect \
                --lto=yes \
                --jobs=\$(nproc) \
                --python-flag=-OO \
                --strip \
                --noinclude-setuptools-metadata=yes \
                --enable-plugin=anti-bloat \
                --include-data-dir=/build/agent/skills=skills \
                --include-data-dir=/build/agent/optional-skills=optional-skills \
                --include-data-dir=/build/agent/locales=locales \
                -m intellect_cli.main \
            && \
            python -m nuitka \
                --${MODE} \
                --output-dir=/output \
                --output-filename=intellect-agent \
                --lto=yes \
                --jobs=\$(nproc) \
                --python-flag=-OO \
                --strip \
                --noinclude-setuptools-metadata=yes \
                --enable-plugin=anti-bloat \
                --include-data-dir=/build/agent/skills=skills \
                --include-data-dir=/build/agent/optional-skills=optional-skills \
                --include-data-dir=/build/agent/locales=locales \
                -m run_agent \
            && \
            python -m nuitka \
                --${MODE} \
                --output-dir=/output \
                --output-filename=intellect-acp \
                --lto=yes \
                --jobs=\$(nproc) \
                --python-flag=-OO \
                --strip \
                --noinclude-setuptools-metadata=yes \
                --enable-plugin=anti-bloat \
                -m acp_adapter.entry
        "

    for bin_name in intellect intellect-agent intellect-acp; do
        if [[ -f "${dist_dir}/bin/${bin_name}" ]]; then
            log_info "  [OK] ${bin_name}"
        elif [[ -f "${dist_dir}/bin/${bin_name}.bin" ]]; then
            mv "${dist_dir}/bin/${bin_name}.bin" "${dist_dir}/bin/${bin_name}"
            log_info "  [OK] ${bin_name}"
        else
            log_warn "  [MISSING] ${bin_name}"
        fi
    done

    # Build webui binary
    log_info "Building intellect-webui..."
    docker run \
        --platform "linux/${docker_arch}" \
        --rm \
        -u "$(id -u):$(id -g)" \
        -v "${WEBUI_REPO}:/build/webui:ro" \
        -v "${dist_dir}/bin:/output:rw" \
        -e NUITKA_MODE="${MODE}" \
        "${BUILDER_IMAGE}:${docker_arch}" \
        bash -c "
            pip install nuitka pyyaml cryptography && \
            python -m nuitka \
                --${MODE} \
                --output-dir=/output \
                --output-filename=intellect-webui \
                --lto=yes \
                --jobs=\$(nproc) \
                --python-flag=-OO \
                --strip \
                --noinclude-setuptools-metadata=yes \
                --enable-plugin=anti-bloat \
                --include-data-dir=/build/webui/static=webui \
                --assume-yes-for-downloads \
                /build/webui/server.py
        "

    if [[ -f "${dist_dir}/bin/intellect-webui" ]]; then
        log_info "  [OK] intellect-webui"
    elif [[ -f "${dist_dir}/bin/intellect-webui.bin" ]]; then
        mv "${dist_dir}/bin/intellect-webui.bin" "${dist_dir}/bin/intellect-webui"
        log_info "  [OK] intellect-webui"
    else
        log_warn "  [MISSING] intellect-webui"
    fi

    # Extract static files
    log_info "Copying webui static files..."
    cp -r "${WEBUI_REPO}/static/"* "${dist_dir}/webui/"
    log_info "  [OK] webui/ ($(find "${dist_dir}/webui" -type f | wc -l | tr -d ' ') files)"

    # Copy assets
    cp "${INTELLECT_ROOT}/assets/ctl.sh" "${dist_dir}/"
    cp "${INTELLECT_ROOT}/assets/env.sh" "${dist_dir}/"
    chmod +x "${dist_dir}/ctl.sh" "${dist_dir}/env.sh"

    sed -e "s/{{VERSION}}/${VERSION}/g" \
        -e "s/{{PLATFORM}}/Linux/g" \
        -e "s/{{ARCH}}/${docker_arch}/g" \
        "${INTELLECT_ROOT}/assets/README.dist.md" > "${dist_dir}/README.md"

    # Package
    cd "${DIST_DIR}"
    PKG_NAME="intellect-dist-${target}-${VERSION}"
    tar -czf "${PKG_NAME}.tar.gz" "$(basename "$dist_dir")"

    log_info "[OK] linux/${docker_arch} → ${PKG_NAME}.tar.gz ($(du -h "${PKG_NAME}.tar.gz" | cut -f1))"
}

# ── Main ──────────────────────────────────────────────────────────────
for arch in "${TARGET_ARCHS[@]}"; do
    build_builder_image "$arch"
    build_for_arch "$arch"
done

log_info ""
log_info "=== Linux Build Complete ==="
ls -la "${DIST_DIR}"/*.tar.gz 2>/dev/null || true
