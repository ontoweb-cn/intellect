# Intellect — AI 에이전트 플랫폼

**Intellect Agent** 런타임과 **Intellect WebUI** 브라우저 인터페이스를 통합한 AI 에이전트 플랫폼입니다.

## 배포 방법

### 1. macOS 네이티브

| 아키텍처 | 패키지 |
|---------|---------|
| Apple Silicon (M1/M2/M3) | `intellect-dist-darwin-arm64-{version}.tar.gz` |
| Intel Mac | `intellect-dist-darwin-amd64-{version}.tar.gz` |

```bash
tar -xzf intellect-dist-darwin-arm64-{version}.tar.gz
cd intellect-dist-darwin-arm64
cp .env.example .env
# .env 파일에 API 키 설정
source ./env.sh
./ctl.sh start
# 브라우저에서 http://127.0.0.1:9119 열기
```

### 2. Linux 네이티브

| 아키텍처 | 패키지 |
|---------|---------|
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

# 또는 매니페스트 직접 적용
kubectl apply -f k8s-manifests/
```

## CLI 명령어

```bash
source ./env.sh
./bin/intellect chat              # 대화형 채팅
./bin/intellect gateway run       # 메시징 게이트웨이 실행
./bin/intellect cron list         # 크론 작업 목록
./bin/intellect doctor            # 시스템 진단
```

## WebUI 관리

```bash
./ctl.sh start       # 데몬 시작
./ctl.sh stop        # 중지
./ctl.sh restart     # 재시작
./ctl.sh status      # 상태 확인
./ctl.sh logs        # 로그 보기
```

## 설정

`.env.example`을 `.env`로 복사 후 편집:

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `OPENAI_API_KEY` | — | OpenAI API 키 |
| `ANTHROPIC_API_KEY` | — | Anthropic API 키 |
| `INTELLECT_WEBUI_HOST` | `127.0.0.1` | WebUI 바인드 주소 |
| `INTELLECT_WEBUI_PORT` | `9119` | WebUI 포트 |

## 요구사항

- **네이티브**: macOS 12+ 또는 Linux (glibc 2.28+), Python 불필요
- **Docker**: Docker 20.10+
- **Kubernetes**: Kubernetes 1.24+, Helm 3 (선택)

## 지원

- GitHub: https://github.com/ONTOWEB/intellect-agent
- Docker Hub: https://hub.docker.com/u/ontoweb
