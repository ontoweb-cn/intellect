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
    ensure_buildx_builder intellect-builder
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
                --assume-yes-for-downloads \
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
                --assume-yes-for-downloads \
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
                --assume-yes-for-downloads \
                -m acp_adapter.entry
        "

    for bin_name in intellect intellect-agent intellect-acp; do
        if [[ -f "${dist_dir}/bin/${bin_name}" ]]; then
            log_info "  [OK] ${bin_name}"
        elif [[ -f "${dist_dir}/bin/${bin_name}.bin" ]]; then
            mv "${dist_dir}/bin/${bin_name}.bin" "${dist_dir}/bin/${bin_name}"
            log_info "  [OK] ${bin_name}"
        else
            log_error "  [MISSING] ${bin_name} — Nuitka build failed; aborting before packaging a broken artifact"
            exit 1
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
        log_error "  [MISSING] intellect-webui — Nuitka build failed; aborting before packaging a broken artifact"
        exit 1
    fi

    # Extract static files
    log_info "Copying webui static files..."
    cp -r "${WEBUI_REPO}/static/"* "${dist_dir}/webui/"
    # Drop patch-reject leftovers (*.rej/*.orig) so they never reach a release.
    find "${dist_dir}/webui" -type f \( -name '*.rej' -o -name '*.orig' \) -delete
    log_info "  [OK] webui/ ($(find "${dist_dir}/webui" -type f | wc -l | tr -d ' ') files)"

    # Copy assets
    cp "${INTELLECT_ROOT}/assets/ctl.sh" "${dist_dir}/"
    cp "${INTELLECT_ROOT}/assets/env.sh" "${dist_dir}/"
    chmod +x "${dist_dir}/ctl.sh" "${dist_dir}/env.sh"

    # Ship the configuration template the README/env.sh expect (`cp .env.example .env`).
    if [[ -f "${AGENT_REPO}/.env.example" ]]; then
        cp "${AGENT_REPO}/.env.example" "${dist_dir}/.env.example"
    elif [[ -f "${INTELLECT_ROOT}/assets/.env.example" ]]; then
        cp "${INTELLECT_ROOT}/assets/.env.example" "${dist_dir}/.env.example"
    else
        log_error "No .env.example found (looked in agent repo and assets/); aborting"
        exit 1
    fi

    sed -e "s/{{VERSION}}/${VERSION}/g" \
        -e "s/{{PLATFORM}}/Linux/g" \
        -e "s/{{ARCH}}/${docker_arch}/g" \
        -e "s/{{REQUIREMENTS}}/Linux or Windows WSL2 (glibc 2.31+; e.g. Ubuntu 20.04+, Debian 11+). No Python installation required (binaries are self-contained)./g" \
        -e "s|{{PLATFORM_NOTES}}|> **Windows (WSL2):** this Linux build runs unchanged inside any WSL2 distro. After \`./ctl.sh start\`, open http://127.0.0.1:9119 in your Windows browser — WSL2 forwards localhost automatically. For good performance keep the extracted folder on the WSL filesystem (e.g. \`~/intellect\`), not under \`/mnt/c\`.|g" \
        "${INTELLECT_ROOT}/assets/README.dist.md" > "${dist_dir}/README.md"

    # ── Final gate: never package a distribution missing executables ──────
    for b in intellect intellect-agent intellect-acp intellect-webui; do
        if [[ ! -x "${dist_dir}/bin/${b}" ]]; then
            log_error "Refusing to package: bin/${b} missing or not executable"
            exit 1
        fi
    done

    # Package
    assert_dist_safe_for_release "$dist_dir"
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
