# Intellect — Plataforma de Agente IA

Plataforma unificada de agente IA que integra el tiempo de ejecución de **Intellect Agent** con la interfaz web **Intellect WebUI**.

## Métodos de Distribución

### 1. macOS Nativo

| Arquitectura | Paquete |
|-------------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# Editar .env con tus claves API
source ./env.sh
./ctl.sh start
# Abrir http://127.0.0.1:9119 en el navegador
```

### 2. Linux Nativo

| Arquitectura | Paquete |
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

# O aplicar manifiestos directamente
kubectl apply -f k8s-manifests/
```

## Comandos CLI

```bash
source ./env.sh
./bin/intellect chat              # Chat interactivo
./bin/intellect gateway run       # Iniciar gateway de mensajería
./bin/intellect cron list         # Listar tareas programadas
./bin/intellect doctor            # Diagnóstico del sistema
```

## Gestión de WebUI

```bash
./ctl.sh start       # Iniciar demonio
./ctl.sh stop        # Detener
./ctl.sh restart     # Reiniciar
./ctl.sh status      # Estado y salud
./ctl.sh logs        # Ver registros
```

## Configuración

Copiar `.env.example` a `.env` y editar:

| Variable | Predeterminado | Descripción |
|----------|---------------|-------------|
| `OPENAI_API_KEY` | — | Clave API de OpenAI |
| `ANTHROPIC_API_KEY` | — | Clave API de Anthropic |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | Dirección de enlace WebUI |
| `INTELLECT_WEBUI_PORT` | `9119` | Puerto WebUI |

## Requisitos

- **Nativo**: macOS 12+ o Linux (glibc 2.28+), sin necesidad de Python
- **Docker**: Docker 20.10+
- **Kubernetes**: Kubernetes 1.24+, Helm 3 (opcional)

## Soporte

- GitHub: https://github.com/ONTOWEB/intellect-agent
- Docker Hub: https://hub.docker.com/u/ontoweb
