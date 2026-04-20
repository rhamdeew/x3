.DEFAULT_GOAL := help

-include .env
export

PANEL_PORT ?= 2083
PANEL_USER ?= admin
PANEL_PASS ?= admin
PANEL_PATH ?= /get

PROCESS_NAME ?= nginx

PANEL   := docker compose -f compose.yml
XRAY    := docker compose -f compose.xray.yml

.PHONY: help panel xray down logs status gen-cert gen-env init-panel init-routing export _ensure-cert build rebuild

help: ## Show this help
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@if [ ! -f .env ]; then \
		echo "  \033[33mFirst run:\033[0m cp .env.example .env && nano .env && make panel"; \
	else \
		echo "Panel URL: https://localhost:$(PANEL_PORT)$(PANEL_PATH)"; \
	fi

_ensure-cert:
	@if [ ! -f cert/cert.pem ]; then \
		$(MAKE) --no-print-directory gen-cert; \
	fi

build: ## Build custom Docker images with disguised process name
	@echo "Building relay image ($(PROCESS_NAME))..."
	docker compose -f compose.xray.yml build --build-arg PROCESS_NAME=$(PROCESS_NAME)
	@echo "Building panel image ($(PROCESS_NAME))..."
	docker compose -f compose.yml build --build-arg PROCESS_NAME=$(PROCESS_NAME)
	@echo "Done. Process will appear as '$(PROCESS_NAME)'."

rebuild: ## Force rebuild images (no cache)
	@echo "Rebuilding images (no cache)..."
	docker compose -f compose.xray.yml build --no-cache --build-arg PROCESS_NAME=$(PROCESS_NAME)
	docker compose -f compose.yml build --no-cache --build-arg PROCESS_NAME=$(PROCESS_NAME)
	@echo "Done. Process will appear as '$(PROCESS_NAME)'."

panel: down _ensure-cert ## Switch to 3x-ui panel mode (for reconfiguration)
	@mkdir -p db
	@FIRST_RUN=false; \
	[ ! -f db/x-ui.db ] && FIRST_RUN=true; \
	$(PANEL) up -d; \
	if [ "$$FIRST_RUN" = "true" ]; then \
		printf "First start — waiting for DB init"; \
		until [ -f db/x-ui.db ]; do printf "."; sleep 1; done; \
		sleep 2; \
		echo ""; \
		docker exec \
			-e PANEL_PORT=$(PANEL_PORT) \
			-e PANEL_USER=$(PANEL_USER) \
			-e PANEL_PASS=$(PANEL_PASS) \
			-e PANEL_PATH=$(PANEL_PATH) \
			overseer python3 /scripts/init-panel.py; \
		$(PANEL) restart; \
	fi
	@echo ""
	@echo "Panel: https://localhost:$(PANEL_PORT)$(PANEL_PATH)"
	@echo "When done configuring, run: make xray"

export: ## Export current 3x-ui xray config to db/xray_config.json
	@if ! docker ps -q --filter name=overseer | grep -q .; then \
		echo "ERROR: panel is not running. Start it first: make panel"; \
		exit 1; \
	fi
	docker exec overseer cp /app/bin/config.json /etc/x-ui/xray_config.json
	@echo "Exported to db/xray_config.json"

xray: ## Export config from panel (if running) then switch to standalone Xray
	@if docker ps -q --filter name=overseer | grep -q .; then \
		$(MAKE) --no-print-directory export; \
	elif [ ! -f db/xray_config.json ]; then \
		echo "ERROR: db/xray_config.json not found."; \
		echo "Run 'make panel' first, configure 3x-ui, then run 'make xray'."; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory down
	$(XRAY) up -d
	@echo ""
	@echo "Standalone Xray is running."

down: ## Stop all services
	@$(PANEL) down 2>/dev/null || true
	@$(XRAY) down 2>/dev/null || true

logs: ## Follow logs of the currently running service
	@if docker ps -q --filter name=overseer | grep -q .; then \
		$(PANEL) logs -f; \
	elif docker ps -q --filter name=relay | grep -q .; then \
		$(XRAY) logs -f; \
	else \
		echo "No services running. Use 'make panel' or 'make xray'."; \
	fi

status: ## Show which mode is currently running
	@if docker ps -q --filter name=overseer | grep -q .; then \
		echo "Running: panel mode (3x-ui)"; \
	elif docker ps -q --filter name=relay | grep -q .; then \
		echo "Running: production mode (xray)"; \
	else \
		echo "Stopped. Use 'make panel' or 'make xray'."; \
	fi

gen-env: ## Generate .env with random credentials (keeps PORT and PATH from .env.example)
	@if [ -f .env ]; then \
		echo "ERROR: .env already exists. Remove it first."; \
		exit 1; \
	fi
	@PANEL_USER=$$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 12); \
	PANEL_PASS=$$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24); \
	PANEL_PORT=$$(grep '^PANEL_PORT=' .env.example | cut -d= -f2); \
	PANEL_PATH=$$(grep '^PANEL_PATH=' .env.example | cut -d= -f2); \
	PROCESS_NAME=$$(grep '^PROCESS_NAME=' .env.example | cut -d= -f2); \
	printf 'PROCESS_NAME=%s\nPANEL_USER=%s\nPANEL_PASS=%s\nPANEL_PORT=%s\nPANEL_PATH=%s\n' \
		"$$PROCESS_NAME" "$$PANEL_USER" "$$PANEL_PASS" "$$PANEL_PORT" "$$PANEL_PATH" > .env; \
	echo "Generated .env:"; \
	echo "  PROCESS_NAME=$$PROCESS_NAME"; \
	echo "  PANEL_USER=$$PANEL_USER"; \
	echo "  PANEL_PASS=$$PANEL_PASS"; \
	echo "  PANEL_PORT=$$PANEL_PORT"; \
	echo "  PANEL_PATH=$$PANEL_PATH"

gen-cert: ## Generate self-signed TLS cert for the panel into cert/
	@mkdir -p cert
	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
		-keyout cert/key.pem \
		-out cert/cert.pem \
		-subj "/CN=x-ui-panel" \
		-addext "subjectAltName=IP:127.0.0.1,IP:::1"
	@echo ""
	@echo "Cert generated: cert/cert.pem (valid 10 years)"

init-panel: ## Re-apply all panel settings (port/user/pass/path/cert/routing) and restart
	@if ! docker ps -q --filter name=overseer | grep -q .; then \
		echo "ERROR: panel is not running. Start it first: make panel"; \
		exit 1; \
	fi
	docker exec \
		-e PANEL_PORT=$(PANEL_PORT) \
		-e PANEL_USER=$(PANEL_USER) \
		-e PANEL_PASS=$(PANEL_PASS) \
		-e PANEL_PATH=$(PANEL_PATH) \
		overseer python3 /scripts/init-panel.py
	@$(PANEL) restart

init-routing: ## Re-apply Russia bypass routing rules and restart panel
	@if ! docker ps -q --filter name=overseer | grep -q .; then \
		echo "ERROR: panel is not running. Start it first: make panel"; \
		exit 1; \
	fi
	docker exec overseer python3 /scripts/init-routing.py
	@$(PANEL) restart
