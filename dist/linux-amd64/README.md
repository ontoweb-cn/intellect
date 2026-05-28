# Intellect v0.1.0-254-g7b847d54f — Linux (amd64)

## Quick Start

### 1. Extract

```bash
tar -xzf intellect-dist-Linux-amd64-v0.1.0-254-g7b847d54f.tar.gz
cd intellect-dist-Linux-amd64
```

### 2. Configure

```bash
# Copy and edit the environment template
cp .env.example .env
# Add your API keys and configuration
```

### 3. Start WebUI

```bash
# Load environment and start the web interface
source ./env.sh
./ctl.sh start
```

Open http://127.0.0.1:9119 in your browser.

### 4. Run CLI

```bash
source ./env.sh
./bin/intellect chat
```

## Directory Layout

```
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

## Managing the WebUI

```bash
./ctl.sh start       # Start as background daemon
./ctl.sh stop        # Stop the daemon
./ctl.sh restart     # Restart
./ctl.sh status      # Show status and health
./ctl.sh logs        # View logs (tail -f)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | Bind address |
| `INTELLECT_WEBUI_PORT` | `9119` | Listen port |
| `INTELLECT_WEBUI_STATIC_DIR` | `./webui` | Frontend files path |
| `INTELLECT_WEBUI_STATE_DIR` | `~/.intellect/webui` | State directory |

## Requirements

- macOS 12+ (Apple Silicon or Intel)
- No Python installation required (binaries are self-contained)
