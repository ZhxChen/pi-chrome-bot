.PHONY: help build up down logs ps shell smoke clean

COMPOSE ?= docker compose -f docker-compose.dev.yml

help:
	@echo "Targets:"
	@echo "  make build       Build the app image (omp installed from npm)"
	@echo "  make up          docker compose up -d"
	@echo "  make down        docker compose down"
	@echo "  make logs         Tail logs from all services"
	@echo "  make ps           Show running services"
	@echo "  make shell        Open a shell inside the app container"
	@echo "  make smoke        Port-reachability smoke test (writes to tmp/)"
	@echo "  make clean        docker compose down + remove the app image"

# omp is installed from npm inside app/Dockerfile (no separate base image to
# build). To change any version (BUN_VERSION, OMP_VERSION, TTYD_VERSION),
# edit the corresponding build arg in docker-compose.dev.yml.
build:
	$(COMPOSE) build app

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec app bash

smoke:
	@mkdir -p tmp
	@bash scripts/smoke.sh 2>&1 | tee tmp/smoke.log

clean:
	-$(COMPOSE) down -v
	-docker image rm pi-chrome-bot/app:local
