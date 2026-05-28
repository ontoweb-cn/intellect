# Intellect — KI-Agenten-Plattform

Vereinheitlichte KI-Agenten-Plattform, die die **Intellect Agent**-Laufzeitumgebung mit der **Intellect WebUI**-Browseroberfläche integriert.

## Verteilungsmethoden

### 1. macOS Native

| Architektur | Paket |
|-------------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# .env mit API-Schlüsseln bearbeiten
source ./env.sh
./ctl.sh start
# http://127.0.0.1:9119 im Browser öffnen
```

### 2. Linux Native

| Architektur | Paket |
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
docker pull ontoweb/intellect-agent:latest
docker pull ontoweb/intellect-webui:latest
INTELLECT_UID=$(id -u) INTELLECT_GID=$(id -g) docker compose up -d
```

### 4. Kubernetes

```bash
helm repo add ontoweb https://charts.ontoweb.io
helm install intellect ontoweb/intellect \
  --set webui.ingress.host=intellect.example.com

# Oder Manifests direkt anwenden
kubectl apply -f k8s-manifests/
```

## CLI-Befehle

```bash
source ./env.sh
./bin/intellect chat              # Interaktiver Chat
./bin/intellect gateway run       # Nachrichten-Gateway starten
./bin/intellect cron list         # Geplante Aufgaben auflisten
./bin/intellect doctor            # Systemdiagnose
```

## WebUI-Verwaltung

```bash
./ctl.sh start       # Daemon starten
./ctl.sh stop        # Stoppen
./ctl.sh restart     # Neustarten
./ctl.sh status      # Status & Gesundheit
./ctl.sh logs        # Protokolle anzeigen
```

## Konfiguration

`.env.example` nach `.env` kopieren und bearbeiten:

| Variable | Standard | Beschreibung |
|----------|---------|-------------|
| `OPENAI_API_KEY` | — | OpenAI API-Schlüssel |
| `ANTHROPIC_API_KEY` | — | Anthropic API-Schlüssel |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | WebUI-Bindeadresse |
| `INTELLECT_WEBUI_PORT` | `9119` | WebUI-Port |

## Voraussetzungen

- **Native**: macOS 12+ oder Linux (glibc 2.28+), keine Python-Installation nötig
- **Docker**: Docker 20.10+
- **Kubernetes**: Kubernetes 1.24+, Helm 3 (optional)

## Unterstützung

- GitHub: https://github.com/ONTOWEB/intellect-agent
- Docker Hub: https://hub.docker.com/u/ontoweb
