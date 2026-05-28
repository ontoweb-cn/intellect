# Intellect — AI エージェントプラットフォーム

**Intellect Agent** ランタイムと **Intellect WebUI** ブラウザインターフェースを統合した AI エージェントプラットフォームです。

## 配布方法

### 1. macOS ネイティブ

| アーキテクチャ | パッケージ |
|-------------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# .env に API キーを設定
source ./env.sh
./ctl.sh start
# http://127.0.0.1:9119 をブラウザで開く
```

### 2. Linux ネイティブ

| アーキテクチャ | パッケージ |
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

# またはマニフェストを直接適用
kubectl apply -f k8s-manifests/
```

## CLI コマンド

```bash
source ./env.sh
./bin/intellect chat              # 対話型チャット
./bin/intellect gateway run       # メッセージゲートウェイ起動
./bin/intellect cron list         # cron ジョブ一覧
./bin/intellect doctor            # システム診断
```

## WebUI 管理

```bash
./ctl.sh start       # デーモン起動
./ctl.sh stop        # 停止
./ctl.sh restart     # 再起動
./ctl.sh status      # ステータス確認
./ctl.sh logs        # ログ表示
```

## 設定

`.env.example` を `.env` にコピーして編集：

| 変数 | デフォルト | 説明 |
|------|--------|------|
| `OPENAI_API_KEY` | — | OpenAI API キー |
| `ANTHROPIC_API_KEY` | — | Anthropic API キー |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | WebUI バインドアドレス |
| `INTELLECT_WEBUI_PORT` | `9119` | WebUI ポート |

## 必要条件

- **ネイティブ**: macOS 12+ または Linux (glibc 2.28+)、Python 不要
- **Docker**: Docker 20.10+
- **Kubernetes**: Kubernetes 1.24+、Helm 3 (オプション)

## サポート

- GitHub: https://github.com/ONTOWEB/intellect-agent
- Docker Hub: https://hub.docker.com/u/ontoweb
