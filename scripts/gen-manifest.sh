#!/usr/bin/env bash
# =============================================================================
# gen-manifest.sh — generate (and minisign-sign) the auto-update manifest
# =============================================================================
# Produces dist/update.json (+ dist/update.json.minisig) describing the latest
# release. Clients (containers now, native binaries later) fetch this manifest,
# verify the minisign signature against assets/minisign.pub, and *notify* the
# user that a newer version is available — they never auto-apply (notify+confirm).
#
# The manifest is published as a Gitee/GitHub Release asset by release.sh.
#
# Usage:
#   ./scripts/gen-manifest.sh --version v1.0.0
#   ./scripts/gen-manifest.sh --version v1.0.0 --key ~/.minisign/intellect.key
#
# Signing key resolution (first match wins):
#   --key <path>  |  $MINISIGN_SECRET_KEY (path)
# If no key/minisign is available, the manifest is still written, unsigned,
# with a warning (useful for dry runs / local inspection).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

VERSION=""
REGISTRY="${DOCKER_REGISTRY:-docker.io}"
NAMESPACE="${DOCKER_NAMESPACE:-ontoweb}"
GITEE_REPO="${GITEE_REPO:-ontoweb/intellect}"
GITHUB_REPO="${GITHUB_REPO:-ontoweb-cn/intellect}"
MIN_SUPPORTED="${MIN_SUPPORTED:-}"
NOTES="${NOTES:-}"
NOTES_FILE=""
OUT_DIR="${DIST_DIR}"
SIGN_KEY="${MINISIGN_SECRET_KEY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)        VERSION="$2"; shift 2 ;;
        --registry)       REGISTRY="$2"; shift 2 ;;
        --namespace)      NAMESPACE="$2"; shift 2 ;;
        --gitee-repo)     GITEE_REPO="$2"; shift 2 ;;
        --github-repo)    GITHUB_REPO="$2"; shift 2 ;;
        --min-supported)  MIN_SUPPORTED="$2"; shift 2 ;;
        --notes)          NOTES="$2"; shift 2 ;;
        --notes-file)     NOTES_FILE="$2"; shift 2 ;;
        --out)            OUT_DIR="$2"; shift 2 ;;
        --key)            SIGN_KEY="$2"; shift 2 ;;
        --help|-h)        sed -n '2,30p' "$0"; exit 0 ;;
        *)                log_error "Unknown option: $1"; exit 1 ;;
    esac
done

VERSION="${VERSION:-$(get_version)}"
DOCKER_TAG="${VERSION#v}"
mkdir -p "${OUT_DIR}"

require_cmd python3

if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
    NOTES="$(cat "$NOTES_FILE")"
fi

# ── Portable sha256 ───────────────────────────────────────────────────────
sha256_of() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        log_error "Neither sha256sum nor shasum found"; exit 1
    fi
}

# ── Collect native tarballs already present in dist (optional / future) ────
# Names look like: intellect-dist-<os>-<arch>-<version>.tar.gz
NATIVE_LIST_FILE="$(mktemp)"
trap 'rm -f "$NATIVE_LIST_FILE"' EXIT
shopt -s nullglob
for tarball in "${OUT_DIR}"/intellect-dist-*-"${VERSION}".tar.gz; do
    base="$(basename "$tarball")"
    # strip prefix and suffix → "<os>-<arch>"
    stripped="${base#intellect-dist-}"
    platform_arch="${stripped%-${VERSION}.tar.gz}"
    os="${platform_arch%-*}"
    arch="${platform_arch##*-}"
    sha="$(sha256_of "$tarball")"
    size="$(wc -c < "$tarball" | tr -d ' ')"
    echo "${os} ${arch} ${base} ${sha} ${size}" >> "$NATIVE_LIST_FILE"
done
shopt -u nullglob

# ── Emit JSON (python handles escaping safely) ────────────────────────────
MANIFEST="${OUT_DIR}/update.json"
VERSION="$VERSION" DOCKER_TAG="$DOCKER_TAG" REGISTRY="$REGISTRY" NAMESPACE="$NAMESPACE" \
GITEE_REPO="$GITEE_REPO" GITHUB_REPO="$GITHUB_REPO" MIN_SUPPORTED="$MIN_SUPPORTED" \
NOTES="$NOTES" RELEASED="$(date +%Y-%m-%d)" NATIVE_LIST_FILE="$NATIVE_LIST_FILE" \
python3 - > "$MANIFEST" <<'PY'
import json, os

ver    = os.environ["VERSION"]
tag    = os.environ["DOCKER_TAG"]
reg    = os.environ["REGISTRY"]
ns     = os.environ["NAMESPACE"]
gitee  = os.environ["GITEE_REPO"]
github = os.environ["GITHUB_REPO"]
notes  = os.environ.get("NOTES", "")
minsup = os.environ.get("MIN_SUPPORTED", "")

artifacts = {
    "docker": {
        "agent": {"image": f"{reg}/{ns}/intellect-agent", "tag": tag},
        "webui": {"image": f"{reg}/{ns}/intellect-webui", "tag": tag},
    }
}

nf = os.environ.get("NATIVE_LIST_FILE", "")
if nf and os.path.exists(nf):
    with open(nf) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 5:
                continue
            os_, arch, fname, sha, size = parts[:5]
            artifacts[f"{os_}-{arch}"] = {
                "url": f"https://gitee.com/{gitee}/releases/download/{ver}/{fname}",
                "sha256": sha,
                "size": int(size),
            }

manifest = {
    "schema": 1,
    "channel": "stable",
    "version": ver,
    "released": os.environ.get("RELEASED", ""),
    "artifacts": artifacts,
    "mirrors": [
        f"https://gitee.com/{gitee}/releases/download/{ver}",
        f"https://github.com/{github}/releases/download/{ver}",
    ],
}
if minsup:
    manifest["min_supported"] = minsup
if notes:
    manifest["notes"] = notes

print(json.dumps(manifest, indent=2, ensure_ascii=False))
PY

log_info "[OK] wrote ${MANIFEST}"

# ── Sign with minisign ────────────────────────────────────────────────────
if [[ -z "$SIGN_KEY" ]]; then
    log_warn "No minisign key (--key / \$MINISIGN_SECRET_KEY) — manifest is UNSIGNED."
    log_warn "Clients that enforce signatures will reject it. See docs/auto-update.md."
elif ! command -v minisign &>/dev/null; then
    log_warn "minisign not installed — manifest is UNSIGNED. Install: https://github.com/jedisct1/minisign"
elif [[ ! -f "$SIGN_KEY" ]]; then
    log_error "Signing key not found: ${SIGN_KEY}"; exit 1
else
    log_step "Signing manifest with minisign..."
    SIG="${MANIFEST}.minisig"
    # CI keys SHOULD be passwordless (minisign -G -W). If a password is set,
    # pass it on stdin (best effort across minisign versions).
    if [[ -n "${MINISIGN_PASSWORD:-}" ]]; then
        printf '%s\n' "$MINISIGN_PASSWORD" | minisign -S -s "$SIGN_KEY" -m "$MANIFEST" -x "$SIG"
    else
        minisign -S -s "$SIGN_KEY" -m "$MANIFEST" -x "$SIG"
    fi
    log_info "[OK] wrote ${SIG}"

    # Self-verify against the committed public key when available.
    PUBKEY="${INTELLECT_ROOT}/assets/minisign.pub"
    if [[ -f "$PUBKEY" ]] && ! grep -qi "REPLACE" "$PUBKEY"; then
        if minisign -Vm "$MANIFEST" -p "$PUBKEY" >/dev/null 2>&1; then
            log_info "[OK] signature verifies against assets/minisign.pub"
        else
            log_error "Signature does NOT verify against assets/minisign.pub — key mismatch!"
            exit 1
        fi
    fi
fi

log_info ""
log_info "Manifest ready in ${OUT_DIR}/ (update.json[.minisig])"
