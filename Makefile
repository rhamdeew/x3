.DEFAULT_GOAL := help

PANEL   := docker compose -f compose.yml
XRAY    := docker compose -f compose.xray.yml

.PHONY: help panel xray down logs status init-routing gen-cert init-cert _ensure-cert

help: ## Show this help
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@if [ ! -f .env ]; then \
		echo "  \033[33mFirst run:\033[0m cp .env.example .env && nano .env && make panel"; \
	else \
		echo "Panel URL: https://localhost:$${PANEL_PORT:-2083}"; \
	fi

# Auto-generate cert if missing (called as dependency)
_ensure-cert:
	@if [ ! -f cert/cert.pem ]; then \
		$(MAKE) --no-print-directory gen-cert; \
	fi

panel: down _ensure-cert ## Switch to 3x-ui panel mode (for reconfiguration)
	@FIRST_RUN=false; \
	[ ! -f db/x-ui.db ] && FIRST_RUN=true; \
	$(PANEL) up -d; \
	if [ "$$FIRST_RUN" = "true" ]; then \
		printf "First start — waiting for DB init"; \
		until [ -f db/x-ui.db ]; do printf "."; sleep 1; done; \
		sleep 2; \
		echo ""; \
		python3 scripts/init-cert.py; \
		python3 scripts/init-routing.py; \
		$(PANEL) restart; \
	fi
	@echo ""
	@echo "Panel: https://localhost:$${PANEL_PORT:-2083}"
	@echo "When done configuring, run: make xray"

xray: ## Switch to standalone Xray (production mode)
	@if [ ! -f db/xray_config.json ]; then \
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

gen-cert: ## Generate self-signed TLS cert for the panel into cert/
	@mkdir -p cert
	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
		-keyout cert/key.pem \
		-out cert/cert.pem \
		-subj "/CN=x-ui-panel" \
		-addext "subjectAltName=IP:127.0.0.1,IP:::1"
	@echo ""
	@echo "Cert generated: cert/cert.pem (valid 10 years)"

init-cert: ## Manually apply SSL cert to existing 3x-ui DB, then restart panel
	@if [ ! -f db/x-ui.db ]; then \
		echo "ERROR: db/x-ui.db not found. Start panel first: make panel"; \
		exit 1; \
	fi
	@python3 scripts/init-cert.py
	@$(PANEL) restart

init-routing: ## Manually apply Russia bypass routing to existing 3x-ui DB, then restart panel
	@if [ ! -f db/x-ui.db ]; then \
		echo "ERROR: db/x-ui.db not found. Start panel first: make panel"; \
		exit 1; \
	fi
	@python3 scripts/init-routing.py
	@$(PANEL) restart
