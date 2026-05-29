# Intellect — AI Agent Platform

A unified AI agent platform combining the **Intellect Agent** runtime with the **Intellect WebUI** browser interface.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Intellect                      │
│                                                 │
│  ┌──────────────────┐  ┌──────────────────────┐ │
│  │  intellect-agent │  │  intellect-webui     │ │
│  │  • CLI (chat)    │  │  • Browser interface │ │
│  │  • Gateway       │  │  • Session management│ │
│  │  • Cron scheduler│  │  • File workspace    │ │
│  │  • ACP server    │  │  • Terminal emulator │ │
│  └──────────────────┘  └──────────────────────┘ │
│            │                      │             │
│            └──────────┬───────────┘             │
│                       │                         │
│              ~/.intellect/ (shared state)       │
└─────────────────────────────────────────────────┘
```

## Distribution Methods

### 1. macOS Native

| Architecture | Package |
|-------------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

> macOS tarballs are not cross-compilable and may not be published as
> prebuilt artifacts. If no download is available for your release, build one
> locally on a Mac of the matching architecture: `make macos`
> (output lands in `dist/`).

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# Edit .env with your API keys
source ./env.sh
./ctl.sh start
# Open http://127.0.0.1:9119
```

### 2. Linux Native

| Architecture | Package |
|-------------|---------|
| x86_64 | `intellect-dist-linux-amd64-{version}.tar.gz` |
| ARM64 | `intellect-dist-linux-arm64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-linux-amd64-{version}.tar.gz
cd intellect-dist-linux-amd64
cp .env.example .env
source ./env.sh
./ctl.sh start
```

### 3. Docker

```bash
# Pull images (published builds)
docker pull ontoweb/intellect-agent:latest
docker pull ontoweb/intellect-webui:latest

# Start with docker-compose (run from the docker/ directory)
cd docker
INTELLECT_UID=$(id -u) INTELLECT_GID=$(id -g) docker compose up -d
```

> If the images are not published for your registry/namespace yet, build them
> locally first: `make docker-amd64` (or `make docker-arm64`). Use
> `./scripts/build-docker.sh --arch amd64 --version <ver>` without `--push` to
> build into the local Docker daemon only.
>
> The **webui image is self-contained**: its Python runtime venv (including
> `intellect-agent[all]`) is installed at image-build time, so containers start
> with no first-boot network access and no agent-source mount. Because the build
> pulls in the agent source as a named build context, the webui image must be
> built via `scripts/build-docker.sh` (buildx) — a bare
> `docker build ../intellect-webui` will not resolve the `intellect-agent`
> context. The build expects the agent checkout at `../intellect-agent`.

#### Using the agent CLI

The compose `agent` service runs the **gateway daemon** (`gateway run`); it does
not need a terminal. To use the interactive CLI, attach to the running
container with a TTY, or run a one-shot prompt:

```bash
# Interactive chat against the running compose container (TTY required)
docker exec -it intellect-agent intellect chat

# One-shot, non-interactive prompt (no TTY needed — good for scripts/CI)
docker exec intellect-agent intellect chat -q "Summarize today's news"

# Run the image directly as an interactive CLI (note the -it)
docker run -it --rm -v ~/.intellect:/opt/data ontoweb/intellect-agent
```

> **`Warning: Input is not a terminal (fd=0).`** — harmless. It only means the
> interactive CLI was started without a TTY. Add `-it` for interactive use, or
> use `chat -q "..."` for non-interactive runs. The `gateway run` daemon does
> not need a TTY and can ignore this.

> **`tirith security scanner enabled but not available …`** — harmless. `tirith`
> is an optional pre-exec command scanner, downloaded on first run from GitHub
> releases to `/opt/data/bin/tirith`. If the container has no network to
> github.com (or the download has not finished), command security falls back to
> built-in pattern matching. To silence it, either allow outbound network so it
> can download, or disable it in `~/.intellect/config.yaml`:
>
> ```yaml
> security:
>   tirith_enabled: false
> ```

### 4. Kubernetes

```bash
# Using Helm
helm repo add ontoweb https://charts.ontoweb.io
helm install intellect ontoweb/intellect \
  --set webui.ingress.host=intellect.example.com

# Using raw manifests
kubectl apply -f k8s-manifests/
```

## CLI Commands

```bash
source ./env.sh

# Interactive chat
./bin/intellect chat

# Run messaging gateway (Telegram, Discord, Slack, etc.)
./bin/intellect gateway run

# Manage cron jobs
./bin/intellect cron list
./bin/intellect cron add "0 9 * * *" "Summarize today's news"

# Check system status
./bin/intellect doctor

# Show version
./bin/intellect version

# ACP (Agent Client Protocol) server — JSON-RPC over stdio,
# normally launched by an ACP-compatible client/editor rather than by hand
./bin/intellect-acp
```

## WebUI Management

```bash
./ctl.sh start       # Start as daemon
./ctl.sh stop        # Stop daemon
./ctl.sh restart     # Restart daemon
./ctl.sh status      # Show status and health
./ctl.sh logs        # View logs (tail -f)
```

## Configuration

Copy `.env.example` to `.env` and configure:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | — | OpenAI API key |
| `ANTHROPIC_API_KEY` | — | Anthropic API key |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | WebUI bind address |
| `INTELLECT_WEBUI_PORT` | `9119` | WebUI listen port |
| `INTELLECT_WEBUI_STATIC_DIR` | `./webui` | Frontend files path |
| `INTELLECT_WEBUI_STATE_DIR` | `~/.intellect/webui` | State directory |

## Directory Layout

```
intellect-dist-{platform}-{arch}/
├── bin/
│   ├── intellect              # Main CLI
│   ├── intellect-agent        # Agent runner
│   ├── intellect-acp          # ACP protocol server
│   └── intellect-webui        # Web interface server
├── webui/                     # Frontend static files
├── ctl.sh                     # WebUI process manager
├── env.sh                     # Environment loader
├── .env.example               # Configuration template
└── README.md                  # This file
```

## Requirements

### Native Distribution
- macOS 12+ or Linux (glibc 2.28+)
- No Python installation required

### Docker
- Docker 20.10+
- docker-compose (optional)

### Kubernetes
- Kubernetes 1.24+
- Helm 3 (optional)

## Support

- GitHub: https://github.com/ontoweb-cn/intellect
- Docker Hub: https://hub.docker.com/u/ontoweb
