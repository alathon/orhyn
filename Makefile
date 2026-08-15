ARGS ?=
POWERSHELL ?= pwsh

ifeq ($(OS),Windows_NT)
RUN_ORCHESTRATOR = $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run_orchestrator.ps1
RUN_ZONE = $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run_zone.ps1
RUN_SERVERS = $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run_servers.ps1
RUN_SERVER_AND_CLIENT = $(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File scripts/run_server_and_client.ps1
RUN_E2E = ./scripts/run_e2e.sh
else
RUN_ORCHESTRATOR = ./scripts/run_orchestrator.sh
RUN_ZONE = ./scripts/run_zone.sh
RUN_SERVERS = ./scripts/run_servers.sh
RUN_SERVER_AND_CLIENT = ./scripts/run_server_and_client.sh
RUN_E2E = ./scripts/run_e2e.sh
endif

.PHONY: help orchestrator run-orchestrator run_orchestrator zone run-zone run_zone servers run-servers run_servers server-and-client server_and_client run-server-and-client run_server_and_client e2e e2e-impaired

help:
	@printf '%s\n' \
		'Targets:' \
		'  make orchestrator ARGS="..."' \
		'  make zone ARGS="--zone mvp --port 4242"' \
		'  make servers ARGS="--headless"' \
		'  make server-and-client' \
		'  make e2e' \
		'  make e2e-impaired' \
		'' \
		'Set GODOT_BIN or GO_BIN to override executable names on Unix-like systems.'

orchestrator run-orchestrator run_orchestrator:
	@$(RUN_ORCHESTRATOR) $(ARGS)

zone run-zone run_zone:
	@$(RUN_ZONE) $(ARGS)

servers run-servers run_servers:
	@$(RUN_SERVERS) $(ARGS)

server-and-client server_and_client run-server-and-client run_server_and_client:
	@$(RUN_SERVER_AND_CLIENT) $(ARGS)

e2e:
	@$(RUN_E2E) $(ARGS)

e2e-impaired:
	@./scripts/run_e2e_impaired.sh $(ARGS)
