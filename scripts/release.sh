#!/usr/bin/env bash
# =============================================================================
# release.sh — Intellect unified release script
# =============================================================================
# Orchestrates: Docker image build & push → native binary builds →
#               Gitee Release + GitHub Release
#
# Usage:
#   ./scripts/release.sh --version v1.0.0                            # full release
#   ./scripts/release.sh --version v1.0.0 --dry-run                  # preview only
#   ./scripts/release.sh --version v1.0.0 --skip-native              # Docker only
#   ./scripts/release.sh --version v1.0.0 --skip-docker              # native + release only
#   ./scripts/release.sh --version v1.0.0 --skip-gitee               # skip Gitee
#   ./scripts/release.sh --version v1.0.0 --skip-github              # skip GitHub
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ── Defaults ──────────────────────────────────────────────────────────────
VERSION=""
DRY_RUN=false
SKIP_DOCKER=false
SKIP_NATIVE=false
SKIP_LINUX=false
SKIP_MACOS=false
SKIP_GITEE=false
SKIP_GITHUB=false
SKIP_SYNC=false
GITEE_TOKEN="${GITEE_TOKEN:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REGISTRY="${DOCKER_REGISTRY:-docker.io}"
NAMESPACE="${DOCKER_NAMESPACE:-ontoweb}"
NATIVE_ARCHS="x86_64,arm64"
MACOS_ARCH="${MACOS_ARCH:-}"
GIT_REPO="${INTELLECT_ROOT}"
GITEE_REPO="${GITEE_REPO:-ontoweb/intellect}"
GITHUB_REPO="${GITHUB_REPO:-ontoweb-cn/intellect}"

# ── Parse args ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)       VERSION="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --skip-docker)   SKIP_DOCKER=true; shift ;;
        --skip-native)   SKIP_NATIVE=true; shift ;;
        --skip-linux)    SKIP_LINUX=true; shift ;;
        --skip-macos)    SKIP_MACOS=true; shift ;;
        --skip-gitee)    SKIP_GITEE=true; shift ;;
        --skip-github)   SKIP_GITHUB=true; shift ;;
        --skip-sync)     SKIP_SYNC=true; shift ;;
        --gitee-token)   GITEE_TOKEN="$2"; shift 2 ;;
        --github-token)  GITHUB_TOKEN="$2"; shift 2 ;;
        --gitee-repo)    GITEE_REPO="$2"; shift 2 ;;
        --github-repo)   GITHUB_REPO="$2"; shift 2 ;;
        --registry)      REGISTRY="$2"; shift 2 ;;
        --arch)          NATIVE_ARCHS="$2"; shift 2 ;;
        --repo)          GIT_REPO="$2"; shift 2 ;;
        --help|-h)       sed -n '2,16p' "$0"; exit 0 ;;
        *)               log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Validate ───────────────────────────────────────────────────────────────
if [[ -z "$VERSION" ]]; then
    VERSION="$(get_version)"
    log_warn "No --version specified, using detected version: $VERSION"
fi

DOCKER_TAG="${VERSION#v}"

banner "Intellect Release — ${VERSION}"

if $DRY_RUN; then
    log_warn "DRY RUN — nothing will be pushed or uploaded"
fi

require_cmd git

# ── Ensure local git repo ──────────────────────────────────────────────────
if ! git -C "${GIT_REPO}" rev-parse --git-dir &>/dev/null; then
    log_step "Initializing git repository in ${GIT_REPO}..."
    if $DRY_RUN; then
        log_info "[dry-run] Would run: git init ${GIT_REPO}"
    else
        git -C "${GIT_REPO}" init
        git -C "${GIT_REPO}" add -A
        git -C "${GIT_REPO}" commit -m "Initial commit" || true
    fi
fi

# ── Sync sub-repos ────────────────────────────────────────────────────────
if ! $SKIP_SYNC; then
    log_step "Syncing sub-repositories..."

    sync_repo() {
        local path="$1" label="$2"
        if [[ ! -d "$path" ]]; then
            log_warn "${label} not found at ${path}, skipping"
            return
        fi
        if [[ -n "$VERSION" ]] && git -C "$path" rev-parse "${VERSION}" >/dev/null 2>&1; then
            log_info "${label}: checking out ${VERSION}..."
            if ! $DRY_RUN; then
                git -C "$path" fetch --tags origin
                git -C "$path" checkout "${VERSION}"
            fi
        else
            log_info "${label}: pulling latest main..."
            if ! $DRY_RUN; then
                git -C "$path" fetch origin
                git -C "$path" checkout main 2>/dev/null || git -C "$path" checkout master 2>/dev/null || true
                git -C "$path" pull origin main 2>/dev/null || git -C "$path" pull origin master 2>/dev/null || true
                git -C "$path" fetch --tags origin
            fi
        fi
        log_info "  [OK] ${label}: $(git -C "$path" log --oneline -1)"
    }

    if $DRY_RUN; then
        log_info "[dry-run] Would sync ${AGENT_REPO} and ${WEBUI_REPO}"
    else
        sync_repo "${AGENT_REPO}" "intellect-agent"
        sync_repo "${WEBUI_REPO}" "intellect-webui"
    fi
else
    log_info "Skipping sub-repo sync (--skip-sync)"
fi

# ── Agent version coherence (see docs/auto-update.md) ─────────────────────
if [[ -d "${AGENT_REPO}" ]]; then
    log_step "Checking intellect-agent version coherence..."
    if $DRY_RUN; then
        log_info "[dry-run] Would run: ./scripts/assert-agent-version.sh --expected ${VERSION}"
    else
        bash "${SCRIPT_DIR}/assert-agent-version.sh" --expected "${VERSION}"
    fi
fi

# ── Git tag ────────────────────────────────────────────────────────────────
log_step "Checking git tag ${VERSION} (repo: ${GIT_REPO})..."
if git -C "${GIT_REPO}" rev-parse "${VERSION}" >/dev/null 2>&1; then
    log_info "Tag ${VERSION} already exists"
else
    if $DRY_RUN; then
        log_info "[dry-run] Would create tag ${VERSION} in ${GIT_REPO}"
    else
        log_info "Creating tag ${VERSION}..."
        git -C "${GIT_REPO}" tag -a "${VERSION}" -m "Release ${VERSION}"
        log_info "[OK] Tag ${VERSION} created"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Docker images
# ═══════════════════════════════════════════════════════════════════════════
if ! $SKIP_DOCKER; then
    log_step "Building and pushing Docker images..."

    docker_args="--arch amd64,arm64 --version ${DOCKER_TAG} --push"
    if [[ "$REGISTRY" != "docker.io" ]]; then
        docker_args="$docker_args --registry $REGISTRY"
    fi

    if $DRY_RUN; then
        log_info "[dry-run] Would run: ./scripts/build-docker.sh $docker_args"
    else
        require_cmd docker
        bash "${SCRIPT_DIR}/build-docker.sh" $docker_args
    fi

    log_info "[OK] Docker images pushed to ${REGISTRY}/${NAMESPACE}/"
else
    log_info "Skipping Docker images (--skip-docker)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Native Linux binaries
# ═══════════════════════════════════════════════════════════════════════════
NATIVE_ARTIFACTS=()

if ! $SKIP_NATIVE && ! $SKIP_LINUX; then
    log_step "Building native Linux binaries (arch: ${NATIVE_ARCHS})..."

    if $DRY_RUN; then
        log_info "[dry-run] Would run: ./scripts/build-linux.sh --arch ${NATIVE_ARCHS} --version ${VERSION}"
    else
        bash "${SCRIPT_DIR}/build-linux.sh" --arch "${NATIVE_ARCHS}" --version "${VERSION}"
    fi

    for tarball in "${DIST_DIR}"/*.tar.gz; do
        if [[ -f "$tarball" ]]; then
            NATIVE_ARTIFACTS+=("$tarball")
            log_info "  [artifact] $(basename "$tarball")"
        fi
    done
else
    log_info "Skipping native Linux binaries"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Native macOS binaries
# ═══════════════════════════════════════════════════════════════════════════
if ! $SKIP_NATIVE && ! $SKIP_MACOS; then
    log_step "Building native macOS binaries..."

    macos_arch="${MACOS_ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"

    if $DRY_RUN; then
        log_info "[dry-run] Would run: ./scripts/build-macos.sh --arch ${macos_arch} --version ${VERSION}"
    else
        bash "${SCRIPT_DIR}/build-macos.sh" --arch "${macos_arch}" --version "${VERSION}"
    fi

    for tarball in "${DIST_DIR}"/*.tar.gz; do
        if [[ -f "$tarball" ]] && [[ ! " ${NATIVE_ARTIFACTS[*]} " =~ " ${tarball} " ]]; then
            NATIVE_ARTIFACTS+=("$tarball")
            log_info "  [artifact] $(basename "$tarball")"
        fi
    done
elif ! $SKIP_NATIVE && $SKIP_MACOS; then
    log_info "Skipping native macOS binaries (--skip-macos)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Auto-update manifest (signed) — see docs/auto-update.md
# ═══════════════════════════════════════════════════════════════════════════
log_step "Generating signed auto-update manifest..."
manifest_args=(
    --version "${VERSION}"
    --registry "${REGISTRY}"
    --namespace "${NAMESPACE}"
    --gitee-repo "${GITEE_REPO}"
    --github-repo "${GITHUB_REPO}"
)
if $DRY_RUN; then
    log_info "[dry-run] Would run: ./scripts/gen-manifest.sh ${manifest_args[*]}"
else
    bash "${SCRIPT_DIR}/gen-manifest.sh" "${manifest_args[@]}"
fi

MANIFEST_FILES=()
[[ -f "${DIST_DIR}/update.json" ]]         && MANIFEST_FILES+=("${DIST_DIR}/update.json")
[[ -f "${DIST_DIR}/update.json.minisig" ]] && MANIFEST_FILES+=("${DIST_DIR}/update.json.minisig")

# Everything uploaded as a release asset: native tarballs + the signed manifest.
UPLOAD_ASSETS=()
[[ ${#NATIVE_ARTIFACTS[@]} -gt 0 ]] && UPLOAD_ASSETS+=("${NATIVE_ARTIFACTS[@]}")
[[ ${#MANIFEST_FILES[@]}   -gt 0 ]] && UPLOAD_ASSETS+=("${MANIFEST_FILES[@]}")

# ── Build release body (shared across Gitee + GitHub) ─────────────────────
build_release_body() {
    local body
    body="## Docker images"$'\n\n'
    body+="| Image | Tag |"$'\n'
    body+="|-------|-----|"$'\n'
    body+="| \`${NAMESPACE}/intellect-agent\` | \`${DOCKER_TAG}\`, \`latest\` |"$'\n'
    body+="| \`${NAMESPACE}/intellect-webui\` | \`${DOCKER_TAG}\`, \`latest\` |"

    if [[ ${#NATIVE_ARTIFACTS[@]} -gt 0 ]]; then
        body+=$'\n\n'"## Native binaries"$'\n'
        for tarball in "${NATIVE_ARTIFACTS[@]}"; do
            body+="- $(basename "$tarball")"$'\n'
        done
    fi
    echo "$body"
}

# ═══════════════════════════════════════════════════════════════════════════
# Gitee Release (via OpenAPI)
# ═══════════════════════════════════════════════════════════════════════════
if ! $SKIP_GITEE; then
    log_step "Creating Gitee Release (gitee.com/${GITEE_REPO})..."

    if [[ -z "$GITEE_TOKEN" ]]; then
        log_error "GITEE_TOKEN is required. Set it via --gitee-token or env var."
        exit 1
    fi
    require_cmd curl jq

    GITEE_API="https://gitee.com/api/v5/repos/${GITEE_REPO}/releases"
    RELEASE_BODY="$(build_release_body)"

    if $DRY_RUN; then
        log_info "[dry-run] Would create Gitee Release ${VERSION} in gitee.com/${GITEE_REPO}"
        log_info "[dry-run] Release body:"
        echo "$RELEASE_BODY"
    else
        EXISTING_ID=$(curl -sSf -H "Authorization: token ${GITEE_TOKEN}" \
            "${GITEE_API}?tag_name=${VERSION}" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2 || true)

        if [[ -n "$EXISTING_ID" ]]; then
            log_warn "Gitee Release ${VERSION} already exists (id=${EXISTING_ID}), uploading artifacts..."
            for artifact in "${UPLOAD_ASSETS[@]}"; do
                log_info "  Uploading $(basename "$artifact")..."
                curl -sSf -X POST \
                    -H "Authorization: token ${GITEE_TOKEN}" \
                    -F "file=@${artifact}" \
                    "${GITEE_API}/${EXISTING_ID}/attach_files" > /dev/null
                log_info "  [OK] $(basename "$artifact")"
            done
        else
            log_info "Creating release ${VERSION}..."
            RESPONSE=$(curl -sSf -X POST \
                -H "Authorization: token ${GITEE_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$(jq -n \
                    --arg tag "$VERSION" \
                    --arg name "$VERSION" \
                    --arg body "$RELEASE_BODY" \
                    '{tag_name: $tag, name: $name, body: $body, prerelease: false}')" \
                "$GITEE_API")

            RELEASE_ID=$(echo "$RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
            log_info "[OK] Release created (id=${RELEASE_ID})"

            for artifact in "${UPLOAD_ASSETS[@]}"; do
                log_info "  Uploading $(basename "$artifact")..."
                curl -sSf -X POST \
                    -H "Authorization: token ${GITEE_TOKEN}" \
                    -F "file=@${artifact}" \
                    "${GITEE_API}/${RELEASE_ID}/attach_files" > /dev/null
                log_info "  [OK] $(basename "$artifact")"
            done
        fi
        log_info "[OK] Gitee Release ${VERSION} published"
    fi
else
    log_info "Skipping Gitee Release (--skip-gitee)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# GitHub Release (via gh CLI)
# ═══════════════════════════════════════════════════════════════════════════
if ! $SKIP_GITHUB; then
    log_step "Creating GitHub Release (github.com/${GITHUB_REPO})..."

    require_cmd gh

    NOTES_FILE="$(mktemp)"
    build_release_body > "$NOTES_FILE"

    if $DRY_RUN; then
        log_info "[dry-run] Would create GitHub Release ${VERSION} in github.com/${GITHUB_REPO}"
        log_info "[dry-run] Release notes:"
        cat "$NOTES_FILE"
    else
        # gh requires GH_TOKEN or GITHUB_TOKEN in env; --repo overrides auto-detection
        GH_REPO_ARGS=(--repo "${GITHUB_REPO}")

        if gh release view "${VERSION}" "${GH_REPO_ARGS[@]}" &>/dev/null; then
            log_warn "GitHub Release ${VERSION} already exists, uploading artifacts..."
            if [[ ${#UPLOAD_ASSETS[@]} -gt 0 ]]; then
                gh release upload "${VERSION}" "${UPLOAD_ASSETS[@]}" \
                    "${GH_REPO_ARGS[@]}" --clobber
            fi
        else
            RELEASE_ARGS=(release create "${VERSION}" \
                --title "${VERSION}" \
                --notes-file "$NOTES_FILE" \
                "${GH_REPO_ARGS[@]}")
            if [[ ${#UPLOAD_ASSETS[@]} -gt 0 ]]; then
                RELEASE_ARGS+=("${UPLOAD_ASSETS[@]}")
            fi
            gh "${RELEASE_ARGS[@]}"
        fi
        log_info "[OK] GitHub Release ${VERSION} published"
    fi

    rm -f "$NOTES_FILE"
else
    log_info "Skipping GitHub Release (--skip-github)"
fi

# ═══════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Release ${VERSION} Complete ==="
if $DRY_RUN; then
    log_warn "This was a dry run. Remove --dry-run to publish."
fi
