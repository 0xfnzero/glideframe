SHELL := /bin/bash

.DEFAULT_GOAL := help
SWIFT_SCRATCH_PATH ?= .swiftpm/build
XCODE_DERIVED_DATA ?= DerivedData
XCODE_RELEASE_DERIVED_DATA ?= DerivedDataRelease
RELEASE_DIR ?= dist/release
APP_VERSION ?= $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" macos/Info.plist 2>/dev/null || echo 0.0.0)
MAC_ARCH ?= $(shell uname -m)
APP_BUNDLE := $(XCODE_DERIVED_DATA)/Build/Products/Debug/GlideFrame.app
RELEASE_APP_BUNDLE := $(XCODE_RELEASE_DERIVED_DATA)/Build/Products/Release/GlideFrame.app
DMG := $(RELEASE_DIR)/GlideFrame-v$(APP_VERSION)-macOS-$(MAC_ARCH).dmg

.PHONY: help install start dev api web mac mac-build mac-swift mac-release mac-dmg desktop desktop-build desktop-package desktop-mac-app desktop-rust-test verify build test typecheck infra migrate

help:
	@echo "GlideFrame commands:"
	@echo "  make start        Start API and web dev servers"
	@echo "  make api          Start only the API server"
	@echo "  make web          Start only the web app"
	@echo "  make mac          Build and open the macOS app bundle"
	@echo "  make mac-build    Build the macOS Debug app bundle"
	@echo "  make mac-swift    Run the SwiftPM executable without an app bundle"
	@echo "  make mac-release  Build the macOS Release app bundle"
	@echo "  make mac-dmg      Build the macOS Release app bundle and package a DMG"
	@echo "  make desktop      Run Tauri in development mode (macOS/Windows)"
	@echo "  make desktop-package Build the Tauri installer for the current OS"
	@echo "  make desktop-mac-app Build and open the packaged macOS Tauri app"
	@echo "  make verify       Run Swift, Rust, API and TypeScript checks"
	@echo "  make build        Build web/API workspaces"
	@echo "  make test         Run API and Swift tests"
	@echo "  make typecheck    Type-check TypeScript workspaces"
	@echo "  make infra        Start local PostgreSQL/Redis/MinIO services"
	@echo "  make migrate      Run API database migrations"

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
	xcodegen generate
	xcodebuild -project GlideFrame.xcodeproj -scheme GlideFrame -configuration Debug -derivedDataPath "$(XCODE_DERIVED_DATA)" build
	bash scripts/sign-macos-app.sh "$(APP_BUNDLE)"

mac-swift:
	swift run --scratch-path $(SWIFT_SCRATCH_PATH) GlideFrame

mac-release:
	xcodegen generate
	xcodebuild -project GlideFrame.xcodeproj -scheme GlideFrame -configuration Release -derivedDataPath "$(XCODE_RELEASE_DERIVED_DATA)" build
	bash scripts/sign-macos-app.sh "$(RELEASE_APP_BUNDLE)"

desktop: node_modules
	npm run dev:desktop

desktop-build: node_modules
	npm run build -w @glideframe/desktop

desktop-package: node_modules
	npm run tauri:build -w @glideframe/desktop

desktop-mac-app: node_modules
	npm run tauri:build -w @glideframe/desktop -- --debug --bundles app
	open "apps/desktop/src-tauri/target/debug/bundle/macos/GlideFrame Desktop.app"

desktop-rust-test:
	cargo test --manifest-path crates/glideframe-recorder/Cargo.toml

verify: typecheck test desktop-rust-test

mac-dmg: mac-release
	@set -euo pipefail; \
		app="$(RELEASE_APP_BUNDLE)"; \
		dmg="$(DMG)"; \
		if [ ! -d "$$app" ]; then \
			echo "Release app bundle not found: $$app"; \
			exit 1; \
		fi; \
		if [ -e "$$dmg" ]; then \
			echo "DMG already exists: $$dmg"; \
			echo "Choose another path with: make mac-dmg DMG=dist/release/GlideFrame-custom.dmg"; \
			exit 1; \
		fi; \
		staging=$$(mktemp -d /tmp/glideframe-dmg.XXXXXX); \
		trap 'rm -rf "$$staging"' EXIT; \
		mkdir -p "$$(dirname "$$dmg")"; \
		ditto "$$app" "$$staging/GlideFrame.app"; \
		ln -s /Applications "$$staging/Applications"; \
		hdiutil create -volname "GlideFrame v$(APP_VERSION)" -srcfolder "$$staging" -fs HFS+ -format UDZO "$$dmg"; \
		hdiutil verify "$$dmg"; \
		shasum -a 256 "$$dmg"; \
		echo "Created $$dmg"

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
