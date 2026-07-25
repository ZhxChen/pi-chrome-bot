.PHONY: help build cert up down logs ps shell smoke clean

COMPOSE ?= docker compose -f docker-compose.dev.yml

help:
	@echo "Targets:"
	@echo "  make build       Build the pi image (pi + agent-browser + pi-web)"
	@echo "  make cert        Pre-generate TLS cert for PUBLIC_HOST (optional; pi auto-mints if missing)"
	@echo "  make up          docker compose up -d"
	@echo "  make down        docker compose down"
	@echo "  make logs         Tail logs from all services"
	@echo "  make ps           Show running services"
	@echo "  make shell        Open a shell inside the pi container"
	@echo "  make smoke        Port-reachability smoke test (writes to tmp/)"
	@echo "  make clean        docker compose down + remove the pi image"
	@echo ""
	@echo "Main UX:  https://localhost:30141  (pi-web + embedded Chrome)"

# Versions are build args in docker-compose.dev.yml. After rebuild, drop
# npm_global if you need the volume to pick up image-baked CLI versions.
build:
	$(COMPOSE) build pi

cert:
	@PUBLIC_HOST="$(or $(PUBLIC_HOST),localhost)" bash scripts/generate-proxy-cert.sh

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec pi bash

smoke:
	@mkdir -p tmp
	@bash scripts/smoke.sh 2>&1 | tee tmp/smoke.log

clean:
	-$(COMPOSE) down -v
	-docker image rm pi-chrome-bot/pi:local
