SHELL := /bin/bash

.DEFAULT_GOAL := help
SWIFT_SCRATCH_PATH ?= .swiftpm/build
XCODE_DERIVED_DATA ?= DerivedData
APP_BUNDLE := $(XCODE_DERIVED_DATA)/Build/Products/Debug/GlideFrame.app

.PHONY: help install start dev api web mac mac-build mac-swift build test typecheck infra migrate

help:
	@echo "GlideFrame commands:"
	@echo "  make start      Start API and web dev servers"
	@echo "  make api        Start only the API server"
	@echo "  make web        Start only the web app"
	@echo "  make mac        Build and open the macOS app bundle"
	@echo "  make mac-swift  Run the SwiftPM executable without an app bundle"
	@echo "  make build      Build web/API workspaces"
	@echo "  make test       Run API and Swift tests"
	@echo "  make typecheck  Type-check TypeScript workspaces"
	@echo "  make infra      Start local PostgreSQL/Redis/MinIO services"
	@echo "  make migrate    Run API database migrations"

install: node_modules

node_modules: package-lock.json package.json
	npm install

start: node_modules
	@echo "Starting GlideFrame API at http://127.0.0.1:4100"
	@echo "Starting GlideFrame web app at http://127.0.0.1:3000"
	@trap 'trap - EXIT; jobs -pr | xargs kill 2>/dev/null || true' EXIT INT TERM; \
		npm run dev:api & \
		npm run dev:web & \
		wait

dev: start

api: node_modules
	npm run dev:api

web: node_modules
	npm run dev:web

mac: mac-build
	open "$(APP_BUNDLE)"

mac-build:
	xcodebuild -project GlideFrame.xcodeproj -scheme GlideFrame -configuration Debug -derivedDataPath "$(XCODE_DERIVED_DATA)" build

mac-swift:
	swift run --scratch-path $(SWIFT_SCRATCH_PATH) GlideFrame

build: node_modules
	npm run build

test: node_modules
	npm test
	swift test --scratch-path $(SWIFT_SCRATCH_PATH)

typecheck: node_modules
	npm run typecheck

infra:
	docker compose up -d

migrate: node_modules
	npm run db:migrate -w @glideframe/api
