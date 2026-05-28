# Intellect Unified Distribution Plan

## Overview

This document describes the unified build and distribution system for the **Intellect** project, which combines two components:

| Component | Repository | Description |
|-----------|-----------|-------------|
| **Intellect Agent** | `intellect-agent` | AI agent runtime (CLI, gateway, ACP server) |
| **Intellect WebUI** | `intellect-webui` | Browser-based web interface |

The `~/workspace/intellect` directory serves as the **distribution output root**, where compiled artifacts from both projects are assembled and packaged.

---

## Distribution Directory Structure

```
~/workspace/intellect/
├── plan.md                           # This document
├── Makefile                          # Top-level build orchestrator
├── scripts/
│   ├── common.sh                     # Shared functions (platform/arch detection, version, logging)
│   ├── build-macos.sh                # macOS native build (Nuitka)
│   ├── build-linux.sh                # Linux native build (Docker-based Nuitka)
│   ├── build-docker.sh               # Docker multi-arch image build & push
│   └── build-k8s.sh                  # K8S manifests + Helm chart package
├── assets/                           # Templates copied into distribution packages
│   ├── ctl.sh                        # Process manager for native WebUI binary
│   ├── env.sh                        # Environment loader for native distributions
│   └── README.dist.md                # Distribution README template
├── docker/
│   ├── Dockerfile.agent              # Agent container image
│   ├── Dockerfile.webui              # WebUI container image
│   ├── Dockerfile.combined           # Combined agent + webui image (optional)
│   ├── Dockerfile.linux-builder      # Linux native compilation container
│   └── docker-compose.yml            # Unified compose (agent + webui)
├── k8s/
│   ├── helm/
│   │   └── intellect/
│   │       ├── Chart.yaml
│   │       ├── values.yaml
│   │       └── templates/
│   │           ├── _helpers.tpl
│   │           ├── agent-statefulset.yaml
│   │           ├── webui-deployment.yaml
│   │           ├── services.yaml
│   │           └── ingress.yaml
│   └── manifests/
│       ├── namespace.yaml
│       ├── agent-statefulset.yaml
│       ├── webui-deployment.yaml
│       ├── services.yaml
│       └── ingress.yaml
└── dist/                             # Build output root
    ├── darwin-amd64/
    ├── darwin-arm64/
    ├── linux-amd64/
    └── linux-arm64/
```

Each `dist/{platform}-{arch}/` directory contains:

```
dist/darwin-arm64/
├── bin/
│   ├── intellect                      # Agent CLI binary
│   ├── intellect-agent                # Agent runner binary
│   ├── intellect-acp                  # ACP server binary
│   └── intellect-webui                # WebUI HTTP server binary
├── webui/                             # Frontend static files (extracted from source)
│   ├── index.html
│   ├── style.css
│   ├── ui.js
│   ├── boot.js
│   ├── messages.js
│   ├── sessions.js
│   ├── panels.js
│   ├── workspace.js
│   ├── terminal.js
│   ├── commands.js
│   ├── i18n.js
│   ├── icons.js
│   ├── login.js
│   ├── sw.js
│   └── vendor/
├── ctl.sh                             # Process manager (manage webui daemon)
├── env.sh                             # Environment variable loader
├── .env.example                       # Environment template
└── README.md                          # Quick start guide
```

---

## Four Distribution Methods

### 1. macOS Native Distribution

**Targets:** `darwin-amd64` (Intel Mac), `darwin-arm64` (Apple Silicon)

**Build host requirement:** macOS with matching architecture. Cross-compilation between Intel and Apple Silicon is not supported by Nuitka.

**Technology:** Nuitka onefile mode — compiles Python to standalone native machine code via C translation + clang.

**Build flow:**

```
build-macos.sh [--arch arm64|amd64] [--version X.Y.Z]
  │
  ├── [1] Detect platform and validate prerequisites
  │      - python3, uv, nuitka, cc (Xcode CLT)
  │
  ├── [2] Build intellect-agent binaries
  │      cd intellect-agent
  │      INTELLECT_BUILD_OUTPUT=../intellect/dist/darwin-${ARCH}/bin \
  │        ./scripts/build_binary.sh --onefile --all
  │      Produces: intellect, intellect-agent, intellect-acp
  │
  ├── [3] Build intellect-webui binary
  │      cd intellect-webui
  │      INTELLECT_WEBUI_OUTPUT=../intellect/dist/darwin-${ARCH}/bin \
  │        ./build.sh --onefile
  │      Nuitka flags: --include-data-dir=static=webui
  │      Produces: intellect-webui
  │
  ├── [4] Extract webui static files to filesystem
  │      cp -r intellect-webui/static/ dist/darwin-${ARCH}/webui/
  │      (Available for user customization; binary also has embedded copy)
  │
  ├── [5] Copy distribution assets
  │      cp assets/ctl.sh dist/darwin-${ARCH}/
  │      cp assets/env.sh dist/darwin-${ARCH}/
  │      cp assets/.env.example dist/darwin-${ARCH}/
  │      Generate README.md from template with version substitution
  │
  └── [6] Package
         tar -czf intellect-dist-darwin-${ARCH}-${VERSION}.tar.gz darwin-${ARCH}/
```

**Artifacts:**
- `intellect-dist-darwin-amd64-{version}.tar.gz`
- `intellect-dist-darwin-arm64-{version}.tar.gz`

---

### 2. Linux Native Distribution

**Targets:** `linux-amd64` (x86_64), `linux-arm64` (aarch64)

**Build host requirement:** Any Linux or macOS with Docker. Uses Docker buildx + QEMU for cross-architecture compilation.

**Technology:** Docker container with Nuitka, compiling against a controlled glibc version for broad compatibility. Target baseline: x86-64-v2 for amd64, ARMv8.0 for arm64.

**Build flow:**

```
build-linux.sh [--arch x86_64,arm64] [--version X.Y.Z]
  │
  ├── [1] Ensure Docker buildx builder with QEMU support
  │      docker buildx create --name intellect-builder --use
  │
  ├── [2] Build linux-builder Docker image (per architecture)
  │      docker build --platform linux/${ARCH} \
  │        -f docker/Dockerfile.linux-builder \
  │        -t intellect-linux-builder:${ARCH} .
  │
  ├── [3] Build agent binaries inside container
  │      docker run --platform linux/${ARCH} \
  │        -v intellect-agent:/build:ro \
  │        -v dist/linux-${ARCH}/bin:/output:rw \
  │        -e OUTPUT_DIR=/output \
  │        intellect-linux-builder:${ARCH} \
  │        /build/scripts/build_binary.sh --onefile --all
  │
  ├── [4] Build webui binary inside container
  │      docker run --platform linux/${ARCH} \
  │        -v intellect-webui:/build:ro \
  │        -v dist/linux-${ARCH}/bin:/output:rw \
  │        intellect-linux-builder:${ARCH} \
  │        nuitka --onefile --include-data-dir=static=webui \
  │          -o /output/intellect-webui /build/server.py
  │
  ├── [5] Extract static files + copy assets (same as macOS)
  │
  └── [6] Package tar.gz per architecture
```

**Artifacts:**
- `intellect-dist-linux-amd64-{version}.tar.gz`
- `intellect-dist-linux-arm64-{version}.tar.gz`

---

### 3. Docker Distribution

**Targets:** `linux/amd64`, `linux/arm64`

**Registry:** Docker Hub under `ontoweb/` namespace.

**Images:**

| Image | Dockerfile | Contents |
|-------|-----------|----------|
| `ontoweb/intellect-agent:{tag}` | `docker/Dockerfile.agent` | Agent runtime (Python 3.12+, system deps, entrypoint) |
| `ontoweb/intellect-webui:{tag}` | `docker/Dockerfile.webui` | WebUI server + `webui/` static files |
| `ontoweb/intellect:{tag}` | `docker/Dockerfile.combined` | Combined image (supervisord manages both processes) |

**Tag strategy:**
- `{version}-amd64`, `{version}-arm64` — architecture-specific tags
- `{version}` — multi-arch manifest list (auto-selects correct arch)
- `latest` — tracks the most recent release

**Dockerfile.agent** (based on existing `intellect-agent/Dockerfile`, with dashboard removed):
```dockerfile
FROM debian:13.4
# System deps, uv, gosu, tini
# Python deps via uv sync
# TUI build via npm
# Entrypoint: tini → entrypoint.sh → intellect
```

**Dockerfile.webui** (based on existing `intellect-webui/Dockerfile`, with static→webui):
```dockerfile
FROM python:3.12-slim
# System deps, uv
# COPY static/ → /apptoo/webui/
# ENV INTELLECT_WEBUI_STATIC_DIR=webui
# Entrypoint: docker_init.bash → server.py
```

**Docker Compose:**
```yaml
services:
  agent:
    image: ontoweb/intellect-agent:latest
    network_mode: host
    volumes:
      - ~/.intellect:/opt/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - INTELLECT_UID=${INTELLECT_UID:-10000}
      - INTELLECT_GID=${INTELLECT_GID:-10000}
    command: ["gateway", "run"]

  webui:
    image: ontoweb/intellect-webui:latest
    ports:
      - "${INTELLECT_WEBUI_PORT:-9119}:9119"
    volumes:
      - ~/.intellect:/home/intellectwebui/.intellect
      - ${WORKSPACE:-~/workspace}:/workspace
    environment:
      - INTELLECT_WEBUI_HOST=0.0.0.0
```

**Build commands:**
```bash
./scripts/build-docker.sh --arch amd64,arm64 --version v1.0.0 --push
```

---

### 4. Kubernetes Distribution

**Deployment model:**

```
┌──────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                           │
│                                                               │
│  ┌──────────────────────────┐  ┌──────────────────────────┐  │
│  │  Agent StatefulSet       │  │  WebUI Deployment         │  │
│  │  replicas: 1             │  │  replicas: 1~N            │  │
│  │  hostNetwork: true       │  │                            │  │
│  │  ┌────────────────────┐  │  │  ┌──────────────────────┐ │  │
│  │  │  agent pod          │  │  │  │  webui pods          │ │  │
│  │  │  image: ontoweb/    │  │  │  │  image: ontoweb/     │ │  │
│  │  │    intellect-agent  │  │  │  │    intellect-webui   │ │  │
│  │  │  PVC: /opt/data     │  │  │  │  port: 9119          │ │  │
│  │  └────────────────────┘  │  │  └──────────────────────┘ │  │
│  └──────────────────────────┘  └──────────────────────────┘  │
│              │                              │                  │
│              │                              │                  │
│  ┌───────────┴──────────────────────────────┴──────────────┐  │
│  │  PersistentVolume (RWO)                                  │  │
│  │  Shared agent state, session files, workspace            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                               │
│  WebUI Service: ClusterIP:9119                                │
│  Ingress: / → webui:9119                                      │
└──────────────────────────────────────────────────────────────┘
```

**Helm chart values:**

```yaml
imageRegistry: docker.io/ontoweb
imageTag: latest

agent:
  enabled: true
  nodeSelector:
    kubernetes.io/arch: amd64
  hostNetwork: true
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests: {cpu: 500m, memory: 2Gi}
    limits: {cpu: 2, memory: 4Gi}

webui:
  enabled: true
  replicas: 1
  nodeSelector:
    kubernetes.io/arch: amd64
  service:
    type: ClusterIP
    port: 9119
  ingress:
    enabled: true
    className: nginx
    host: intellect.example.com
```

**Architecture-specific values:**
- `values-amd64.yaml` — `nodeSelector.kubernetes.io/arch: amd64`, image tag `{version}-amd64`
- `values-arm64.yaml` — `nodeSelector.kubernetes.io/arch: arm64`, image tag `{version}-arm64`

---

## Script Migration Strategy

### How existing scripts are handled per distribution method

| Script | Source Repo | Native Dist | Docker Image | K8S |
|--------|:----------:|:-----------:|:-----------:|:---:|
| `setup-intellect.sh` | agent | Removed (binary is self-contained, no venv needed) | Removed (Dockerfile handles deps) | Removed |
| `start.sh` | webui | Removed (replaced by env.sh + ctl.sh) | Removed (docker_init.bash is entrypoint) | Removed |
| `bootstrap.py` | webui | Removed (binary is self-contained) | Removed | Removed |
| `ctl.sh` | webui | **Modified**: manages Nuitka binary instead of Python bootstrap | Removed (container orchestrator manages lifecycle) | Removed |
| `env.sh` | **new** | **Added**: loads .env before binary execution | N/A | N/A |
| `docker/entrypoint.sh` | agent | N/A | Preserved (UID/GID alignment, directory init) | Preserved |
| `docker_init.bash` | webui | N/A | Preserved (UID/GID alignment, venv setup, dep install) | Preserved |

### ctl.sh modifications for native distribution

The native `ctl.sh` is adapted from the webui `ctl.sh`:

**Removed:**
- Python interpreter detection (`_find_python`)
- `bootstrap.py` invocation
- `REPO_ROOT` references

**Added:**
- Binary auto-discovery: looks for `./bin/intellect-webui` relative to script location
- Direct binary execution: `nohup ./bin/intellect-webui --host ... --port ...`

**Preserved:**
- `start` / `stop` / `restart` / `status` / `logs` subcommands
- PID file management
- Health check via `curl /health`
- `.env` file loading
- Stale process detection and cleanup

### env.sh design

```bash
# Loads environment from .env files, then user can exec binaries
# Usage: source ./env.sh && ./bin/intellect-webui

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Layer 1: distribution .env
[ -f "$SCRIPT_DIR/.env" ] && set -a && source "$SCRIPT_DIR/.env" && set +a

# Layer 2: user home .env (overrides)
[ -f "$HOME/.intellect/.env" ] && set -a && source "$HOME/.intellect/.env" && set +a

export INTELLECT_WEBUI_STATIC_DIR="${INTELLECT_WEBUI_STATIC_DIR:-$SCRIPT_DIR/webui}"
export PATH="$SCRIPT_DIR/bin:$PATH"
```

---

## Required Changes to Existing Projects

### intellect-agent changes

| File | Change | Reason |
|------|--------|--------|
| `Dockerfile` | Remove lines 91-98 (dashboard COPY, npm install, pip install, ENV INTELLECT_WEB_DIST) | Dashboard no longer bundled |
| `docker-compose.yml` | Remove `dashboard` service block (lines 58-71) | Dashboard no longer shipped |
| `scripts/build_binary.sh` | Support `INTELLECT_BUILD_OUTPUT` env var to override `OUTPUT_DIR` | Allow external build orchestrator to specify output path |
| `scripts/build_binary_linux.sh` | Support `INTELLECT_BUILD_OUTPUT` env var to override `OUTPUT_BASE` | Same as above |

### intellect-webui changes

| File | Change | Reason |
|------|--------|--------|
| `api/config.py` | Add `STATIC_DIR = os.getenv("INTELLECT_WEBUI_STATIC_DIR", "webui")`; change `_INDEX_HTML_PATH` to use `STATIC_DIR` | Unify static file path as `webui` |
| `api/routes.py` | Replace 6 occurrences of `"static"` with `config.STATIC_DIR`; update HTML template `src="static/"` → `src="{STATIC_DIR}/"` | Same |
| `build.sh` | Change `--include-data-dir=static=static` → `--include-data-dir=static=webui`; support `INTELLECT_WEBUI_OUTPUT` env var | Nuitka embeds at `webui` path |
| `Dockerfile` | Change `COPY . /apptoo` to include explicit `COPY static/ /apptoo/webui/` | Docker filesystem path aligned |

---

## Top-Level Makefile

```makefile
# ~/workspace/intellect/Makefile

VERSION    ?= $(shell git -C ../intellect-agent describe --tags --always 2>/dev/null || echo "dev")
OUTPUT_DIR := $(CURDIR)/dist
ARCH       ?= $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: all clean

macos:
	./scripts/build-macos.sh --arch $(ARCH) --version $(VERSION) --mode onefile

linux:
	./scripts/build-linux.sh --arch x86_64,arm64 --version $(VERSION) --mode onefile

docker:
	./scripts/build-docker.sh --arch amd64,arm64 --version $(VERSION) --push

docker-amd64:
	./scripts/build-docker.sh --arch amd64 --version $(VERSION) --push

docker-arm64:
	./scripts/build-docker.sh --arch arm64 --version $(VERSION) --push

k8s:
	./scripts/build-k8s.sh --version $(VERSION)

release: macos linux docker k8s

clean:
	rm -rf $(OUTPUT_DIR)
```

---

## CI/CD Workflow

```yaml
# .github/workflows/release.yml (in intellect repo)
name: Intellect Release

on:
  push:
    tags: ['v*']

jobs:
  macos-build:
    strategy:
      matrix:
        include:
          - runner: macos-latest
            arch: arm64
          - runner: macos-13
            arch: amd64
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/build-macos.sh --arch ${{ matrix.arch }} --version ${{ github.ref_name }}
      - uses: actions/upload-artifact@v4
        with:
          name: intellect-dist-darwin-${{ matrix.arch }}
          path: dist/*.tar.gz

  linux-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/build-linux.sh --arch x86_64,arm64 --version ${{ github.ref_name }}
      - uses: actions/upload-artifact@v4
        with:
          name: intellect-dist-linux
          path: dist/*.tar.gz

  docker-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - run: ./scripts/build-docker.sh --arch amd64,arm64 --version ${{ github.ref_name }} --push

  k8s-package:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/build-k8s.sh --version ${{ github.ref_name }}
      - uses: actions/upload-artifact@v4
        with:
          name: intellect-k8s
          path: dist/k8s-*.tar.gz

  release:
    needs: [macos-build, linux-build, docker-build, k8s-package]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
      - uses: softprops/action-gh-release@v2
        with:
          files: |
            intellect-dist-*/*.tar.gz
            intellect-k8s/*.tar.gz
          generate_release_notes: true
```

---

## Implementation Phases

| Phase | Scope | Files Affected |
|-------|-------|---------------|
| **P1** | intellect-webui: `static` → `webui` path migration | `api/config.py`, `api/routes.py`, `build.sh`, `Dockerfile` |
| **P2** | intellect-agent: remove dashboard | `Dockerfile`, `docker-compose.yml` |
| **P3** | intellect: directory structure + Makefile + assets | New files in `~/workspace/intellect/` |
| **P4** | build-macos.sh + build-linux.sh | `scripts/build-macos.sh`, `scripts/build-linux.sh` |
| **P5** | Docker assets | `docker/Dockerfile.*`, `docker/docker-compose.yml` |
| **P6** | K8S assets | `k8s/helm/*`, `k8s/manifests/*` |
| **P7** | Test builds | Run all targets, verify outputs |
| **P8** | Documentation | README files (EN, ZH, JA, KO, ES, FR, DE) |

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `INTELLECT_WEBUI_STATIC_DIR` | `webui` | Path to frontend static files (relative to REPO_ROOT or absolute) |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | WebUI server bind address |
| `INTELLECT_WEBUI_PORT` | `9119` | WebUI server port |
| `INTELLECT_WEBUI_STATE_DIR` | `~/.intellect/webui` | Session and workspace state directory |
| `INTELLECT_WEBUI_DEFAULT_WORKSPACE` | (auto-detected) | Default workspace path |
| `INTELLECT_UID` | `10000` | UID for container user mapping |
| `INTELLECT_GID` | `10000` | GID for container user mapping |
| `INTELLECT_BUILD_OUTPUT` | `build/dist` | Override agent binary output directory |
| `INTELLECT_WEBUI_OUTPUT` | `.` | Override webui binary output directory |
