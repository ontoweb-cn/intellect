#!/usr/bin/env bash
# =============================================================================
# build-k8s.sh — K8S manifests and Helm chart packaging
# =============================================================================
# Generates Kubernetes deployment manifests and packages the Helm chart.
#
# Usage:
#   ./scripts/build-k8s.sh --version v1.0.0
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="$2"; shift 2 ;;
        --help|-h)    sed -n '2,10p' "$0"; exit 0 ;;
        *)            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

VERSION="${VERSION:-$(get_version)}"
K8S_DIR="${INTELLECT_ROOT}/k8s"
DIST_DIR="${INTELLECT_ROOT}/dist"

banner "K8S Package — v${VERSION}"

# ── Update image tags in values.yaml ──────────────────────────────────
log_step "Updating image tags..."

HELM_VALUES="${K8S_DIR}/helm/intellect/values.yaml"
if [[ -f "$HELM_VALUES" ]]; then
    TMP_VALUES="${DIST_DIR}/k8s-values.yaml"
    sed -e "s/imageTag:.*/imageTag: \"${VERSION}\"/g" \
        -e "s|imageRegistry:.*|imageRegistry: docker.io/ontoweb|g" \
        "$HELM_VALUES" > "$TMP_VALUES"
    log_info "  [OK] Updated values.yaml to ${VERSION}"
fi

# ── Update image tags in raw manifests ────────────────────────────────
log_step "Updating raw manifests..."

for manifest in "${K8S_DIR}/manifests/"*.yaml; do
    [[ ! -f "$manifest" ]] && continue
    name=$(basename "$manifest")
    TMP_MANIFEST="${DIST_DIR}/k8s-${name}"
    sed -e "s|image:.*ontoweb/intellect-agent:.*|image: docker.io/ontoweb/intellect-agent:${VERSION}|g" \
        -e "s|image:.*ontoweb/intellect-webui:.*|image: docker.io/ontoweb/intellect-webui:${VERSION}|g" \
        "$manifest" > "$TMP_MANIFEST"
    log_info "  [OK] ${name}"
done

# ── Package Helm chart ────────────────────────────────────────────────
log_step "Packaging Helm chart..."

HELM_CHART="${K8S_DIR}/helm/intellect"
if [[ -f "${HELM_CHART}/Chart.yaml" ]]; then
    # Update Chart version
    sed -i '' -e "s/version:.*/version: ${VERSION#v}/" "${HELM_CHART}/Chart.yaml" 2>/dev/null || \
    sed -i -e "s/version:.*/version: ${VERSION#v}/" "${HELM_CHART}/Chart.yaml"

    if command -v helm &>/dev/null; then
        cd "${DIST_DIR}"
        helm package "${HELM_CHART}" --version "${VERSION#v}" --app-version "${VERSION}"
        log_info "  [OK] Helm chart packaged"
    else
        log_warn "  Helm CLI not found — creating tar.gz manually"
        cd "${K8S_DIR}/helm"
        tar -czf "${DIST_DIR}/intellect-helm-${VERSION}.tar.gz" intellect/
        log_info "  [OK] intellect-helm-${VERSION}.tar.gz"
    fi
fi

# ── Package raw manifests ─────────────────────────────────────────────
log_step "Packaging raw manifests..."
cd "${DIST_DIR}"
tar -czf "intellect-k8s-manifests-${VERSION}.tar.gz" k8s-*.yaml
log_info "  [OK] intellect-k8s-manifests-${VERSION}.tar.gz"

log_info ""
log_info "=== K8S Package Complete ==="
ls -la "${DIST_DIR}"/intellect-k8s* 2>/dev/null || true
ls -la "${DIST_DIR}"/*.tgz 2>/dev/null || true
