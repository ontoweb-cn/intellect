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

Download and extract the tarball for your architecture:

| Architecture | Package |
|-------------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

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
# Pull images
docker pull ontoweb/intellect-agent:latest
docker pull ontoweb/intellect-webui:latest

# Start with docker-compose
INTELLECT_UID=$(id -u) INTELLECT_GID=$(id -g) docker compose up -d
```

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
