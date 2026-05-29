# Intellect {{VERSION}} — {{PLATFORM}} ({{ARCH}})

## Quick Start

### 1. Extract

```bash
tar -xzf intellect-dist-{{PLATFORM}}-{{ARCH}}-{{VERSION}}.tar.gz
cd intellect-dist-{{PLATFORM}}-{{ARCH}}
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

# Interactive chat
./bin/intellect chat

# Show version / run diagnostics
./bin/intellect version
./bin/intellect doctor
```

### 5. Run the ACP server

The ACP (Agent Client Protocol) server lets ACP-compatible editors/clients
drive the agent over stdio. It is a standalone binary:

```bash
source ./env.sh
./bin/intellect-acp
```

It speaks JSON-RPC over stdin/stdout, so it is normally launched by your ACP
client rather than run interactively.

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

- {{REQUIREMENTS}}
