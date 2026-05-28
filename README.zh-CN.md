# Intellect — AI 智能体平台

统一 AI 智能体平台，整合 **Intellect Agent** 运行时与 **Intellect WebUI** 浏览器界面。

## 架构

```
┌─────────────────────────────────────────────────┐
│                  Intellect                        │
│                                                   │
│  ┌──────────────────┐  ┌──────────────────────┐  │
│  │  intellect-agent  │  │  intellect-webui      │  │
│  │  • CLI 对话       │  │  • 浏览器界面         │  │
│  │  • 消息网关       │  │  • 会话管理           │  │
│  │  • 定时任务       │  │  • 文件工作区         │  │
│  │  • ACP 协议服务   │  │  • 终端模拟器         │  │
│  └──────────────────┘  └──────────────────────┘  │
│            │                      │               │
│            └──────────┬───────────┘               │
│                       │                           │
│              ~/.intellect/ (共享状态)              │
└─────────────────────────────────────────────────┘
```

## 四种发行方式

### 1. macOS 原生发行

下载对应架构的压缩包：

| 架构 | 包名 |
|------|------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# 编辑 .env 填入 API 密钥
source ./env.sh
./ctl.sh start
# 浏览器打开 http://127.0.0.1:9119
```

### 2. Linux 原生发行

| 架构 | 包名 |
|------|------|
| x86_64 | `intellect-dist-linux-amd64-{version}.tar.gz` |
| ARM64 | `intellect-dist-linux-arm64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-linux-amd64-{version}.tar.gz
cd intellect-dist-linux-amd64
cp .env.example .env
source ./env.sh
./ctl.sh start
```

### 3. Docker 发行

```bash
docker pull ontoweb/intellect-agent:latest
docker pull ontoweb/intellect-webui:latest
INTELLECT_UID=$(id -u) INTELLECT_GID=$(id -g) docker compose up -d
```

### 4. Kubernetes 发行

```bash
# Helm
helm repo add ontoweb https://charts.ontoweb.io
helm install intellect ontoweb/intellect \
  --set webui.ingress.host=intellect.example.com

# 纯 YAML
kubectl apply -f k8s-manifests/
```

## CLI 命令

```bash
source ./env.sh
./bin/intellect chat              # 交互式对话
./bin/intellect gateway run       # 启动消息网关
./bin/intellect cron list         # 查看定时任务
./bin/intellect doctor            # 系统诊断
./bin/intellect version           # 版本信息
```

## WebUI 管理

```bash
./ctl.sh start       # 后台启动
./ctl.sh stop        # 停止
./ctl.sh restart     # 重启
./ctl.sh status      # 状态与健康检查
./ctl.sh logs        # 查看日志
```

## 配置

复制 `.env.example` 为 `.env` 并编辑：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENAI_API_KEY` | — | OpenAI API 密钥 |
| `ANTHROPIC_API_KEY` | — | Anthropic API 密钥 |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | WebUI 绑定地址 |
| `INTELLECT_WEBUI_PORT` | `9119` | WebUI 监听端口 |

## 目录结构

```
intellect-dist-{platform}-{arch}/
├── bin/                        # 可执行文件
├── webui/                      # 前端静态文件
├── ctl.sh                      # 进程管理
├── env.sh                      # 环境加载
├── .env.example                # 配置模板
└── README.md
```

## 系统要求

### 原生发行
- macOS 12+ 或 Linux (glibc 2.28+)
- 无需安装 Python

### Docker
- Docker 20.10+

### Kubernetes
- Kubernetes 1.24+ / Helm 3 (可选)

## 支持

- GitHub: https://github.com/ONTOWEB/intellect-agent
- Docker Hub: https://hub.docker.com/u/ontoweb
