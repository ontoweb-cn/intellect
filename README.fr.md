# Intellect — Plateforme d'Agent IA

Plateforme unifiée d'agent IA intégrant le runtime **Intellect Agent** avec l'interface navigateur **Intellect WebUI**.

## Méthodes de Distribution

### 1. macOS Natif

| Architecture | Paquet |
|-------------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# Éditer .env avec vos clés API
source ./env.sh
./ctl.sh start
# Ouvrir http://127.0.0.1:9119 dans le navigateur
```

### 2. Linux Natif

| Architecture | Paquet |
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

# Ou appliquer les manifests directement
kubectl apply -f k8s-manifests/
```

## Commandes CLI

```bash
source ./env.sh
./bin/intellect chat              # Chat interactif
./bin/intellect gateway run       # Démarrer la passerelle de messagerie
./bin/intellect cron list         # Lister les tâches planifiées
./bin/intellect doctor            # Diagnostic système
```

## Gestion WebUI

```bash
./ctl.sh start       # Démarrer le démon
./ctl.sh stop        # Arrêter
./ctl.sh restart     # Redémarrer
./ctl.sh status      # État et santé
./ctl.sh logs        # Voir les journaux
```

## Configuration

Copier `.env.example` vers `.env` et éditer :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `OPENAI_API_KEY` | — | Clé API OpenAI |
| `ANTHROPIC_API_KEY` | — | Clé API Anthropic |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | Adresse de liaison WebUI |
| `INTELLECT_WEBUI_PORT` | `9119` | Port WebUI |

## Prérequis

- **Natif** : macOS 12+ ou Linux (glibc 2.28+), Python non requis
- **Docker** : Docker 20.10+
- **Kubernetes** : Kubernetes 1.24+, Helm 3 (optionnel)

## Support

- GitHub : https://github.com/ONTOWEB/intellect-agent
- Docker Hub : https://hub.docker.com/u/ontoweb
