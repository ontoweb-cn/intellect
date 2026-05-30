#!/usr/bin/env bash
# =============================================================================
# build-docker.sh — Docker multi-arch image build and push
# =============================================================================
# Builds and optionally pushes the Intellect Docker images to Docker Hub
# under the ontoweb namespace.
#
# Usage:
#   ./scripts/build-docker.sh --arch amd64,arm64 --version v1.0.0
#   ./scripts/build-docker.sh --arch amd64 --version v1.0.0 --push
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ARCHS=()
VERSION=""
PUSH=false
REGISTRY="${DOCKER_REGISTRY:-docker.io}"
NAMESPACE="${DOCKER_NAMESPACE:-ontoweb}"
IMAGES=("intellect-agent" "intellect-webui")
COMBINED_IMAGE="intellect"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)       IFS=',' read -ra TARGET_ARCHS <<< "$2"; shift 2 ;;
        --version)    VERSION="$2"; shift 2 ;;
        --push)       PUSH=true; shift ;;
        --registry)   REGISTRY="$2"; shift 2 ;;
        --help|-h)    sed -n '2,14p' "$0"; exit 0 ;;
        *)            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ${#TARGET_ARCHS[@]} -eq 0 ]]; then
    TARGET_ARCHS=(amd64 arm64)
fi

VERSION="${VERSION:-$(get_version)}"

banner "Docker Build — ${TARGET_ARCHS[*]} (push=$PUSH)"

require_cmd docker

# Ensure buildx
PLATFORMS=""
for arch in "${TARGET_ARCHS[@]}"; do
    da=$(docker_arch "$arch")
    PLATFORMS="${PLATFORMS}linux/${da},"
done
PLATFORMS="${PLATFORMS%,}"

if [[ ${#TARGET_ARCHS[@]} -gt 1 ]]; then
    ensure_buildx_builder intellect-builder
fi

# Build each image
build_image() {
    local image="$1"
    local dockerfile="${INTELLECT_ROOT}/docker/Dockerfile.${image#intellect-}"
    local full_image="${REGISTRY}/${NAMESPACE}/${image}"

    # For combined image, use Dockerfile.combined
    if [[ "$image" == "intellect" ]]; then
        dockerfile="${INTELLECT_ROOT}/docker/Dockerfile.combined"
    fi

    [[ ! -f "$dockerfile" ]] && log_warn "Dockerfile not found: $dockerfile, skipping $image" && return

    log_step "Building ${full_image}:${VERSION}..."

    local build_args=(
        --platform "$PLATFORMS"
        -f "$dockerfile"
        -t "${full_image}:${VERSION}"
        -t "${full_image}:latest"
    )

    # Per-arch tags
    if [[ ${#TARGET_ARCHS[@]} -eq 1 ]]; then
        build_args+=(-t "${full_image}:${VERSION}-${TARGET_ARCHS[0]}")
    else
        for arch in "${TARGET_ARCHS[@]}"; do
            build_args+=(-t "${full_image}:${VERSION}-${arch}")
        done
    fi

    if $PUSH; then
        build_args+=(--push)
    else
        build_args+=(--load)
    fi

    # Build context: per image
    local context
    case "$image" in
        intellect-agent)  context="${AGENT_REPO}" ;;
        intellect-webui)  context="${INTELLECT_ROOT}" ;;
        intellect)        context="${INTELLECT_ROOT}/.." ;;
        *)                context="${INTELLECT_ROOT}/.." ;;
    esac

    # The webui image pre-builds its runtime binary (including intellect-agent[all])
    # at image-build time. It needs agent + webui sources as named build contexts.
    if [[ "$image" == "intellect-agent" ]]; then
        build_args+=(--build-context "intellect-orchestrator=${INTELLECT_ROOT}")
    fi

    if [[ "$image" == "intellect-webui" ]]; then
        build_args+=(--build-context "intellect-agent=${AGENT_REPO}")
        build_args+=(--build-context "intellect-webui=${WEBUI_REPO}")
        build_args+=(--build-arg "INTELLECT_VERSION=${VERSION}")
    fi

    docker buildx build "${build_args[@]}" "$context"

    log_info "[OK] ${full_image}:${VERSION}"
}

log_step "Building images: ${IMAGES[*]} ${COMBINED_IMAGE}"

for img in "${IMAGES[@]}"; do
    build_image "$img"
done

# Build combined image if Dockerfile exists
if [[ -f "${INTELLECT_ROOT}/docker/Dockerfile.combined" ]]; then
    build_image "$COMBINED_IMAGE"
fi

log_info ""
log_info "=== Docker Build Complete ==="
if $PUSH; then
    log_info "Pushed to: ${REGISTRY}/${NAMESPACE}/"
else
    log_info "Images built locally. Use --push to publish."
fi
