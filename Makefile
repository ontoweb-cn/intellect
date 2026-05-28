# Intellect Unified Distribution
#
# Top-level build orchestrator for all distribution methods.
#
# Usage:
#   make macos                        # macOS native (current arch)
#   make linux                        # Linux native (x86_64 + arm64)
#   make docker                       # Docker multi-arch images
#   make k8s                          # K8S manifests + Helm chart
#   make release                      # All of the above
#
# Environment variables:
#   VERSION        Override version tag (default: git describe)
#   ARCH           Override target arch (default: uname -m)

VERSION    ?= $(shell git -C ../intellect-agent describe --tags --always 2>/dev/null || echo "dev")
OUTPUT_DIR := $(CURDIR)/dist
ARCH       ?= $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: all clean help

help:
	@echo "Intellect Unified Distribution"
	@echo ""
	@echo "Targets:"
	@echo "  make macos          macOS native build (arch=$(ARCH))"
	@echo "  make linux          Linux native build (x86_64 + arm64 via Docker)"
	@echo "  make docker         Docker multi-arch images (build + push)"
	@echo "  make docker-amd64   Docker amd64 only"
	@echo "  make docker-arm64   Docker arm64 only"
	@echo "  make k8s            K8S manifests + Helm chart package"
	@echo "  make release        All distribution methods"
	@echo "  make clean          Remove build artifacts"
	@echo ""
	@echo "Variables: VERSION=$(VERSION) ARCH=$(ARCH)"

# ── Native ───────────────────────────────────────────────────────────

macos:
	@./scripts/build-macos.sh --arch $(ARCH) --version $(VERSION)

linux:
	@./scripts/build-linux.sh --arch x86_64,arm64 --version $(VERSION)

linux-amd64:
	@./scripts/build-linux.sh --arch x86_64 --version $(VERSION)

linux-arm64:
	@./scripts/build-linux.sh --arch arm64 --version $(VERSION)

# ── Docker ────────────────────────────────────────────────────────────

docker:
	@./scripts/build-docker.sh --arch amd64,arm64 --version $(VERSION) --push

docker-amd64:
	@./scripts/build-docker.sh --arch amd64 --version $(VERSION) --push

docker-arm64:
	@./scripts/build-docker.sh --arch arm64 --version $(VERSION) --push

# ── K8S ───────────────────────────────────────────────────────────────

k8s:
	@./scripts/build-k8s.sh --version $(VERSION)

# ── Release ───────────────────────────────────────────────────────────

release: macos linux docker k8s
	@echo ""
	@echo "=========================================="
	@echo "  Release $(VERSION) Complete"
	@echo "=========================================="
	@echo ""
	@ls -la $(OUTPUT_DIR)/*.tar.gz 2>/dev/null || true

clean:
	rm -rf $(OUTPUT_DIR)
	@echo "Cleaned $(OUTPUT_DIR)"
