APP_NAME := NomadDashboard
SCHEME := NomadDashboard
PROJECT := $(APP_NAME).xcodeproj
.DEFAULT_GOAL := help

.PHONY: help bootstrap generate open build run rerun test probe-sources lint archive brand-assets dmg release release-patch release-minor release-major release-dry-run release-setup-notary clean

help: ## Print available make targets
	@printf "\nAvailable commands:\n\n"
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9._-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"

bootstrap: ## Install local project tooling and dependencies
	./scripts/bootstrap.sh

generate: ## Regenerate the Xcode project from project.yml
	./scripts/generate-project.sh

open: ## Open the generated Xcode project
	./scripts/open-project.sh

build: ## Build the app in development configuration
	./scripts/build-dev.sh

run: ## Build and launch the app
	./scripts/run-dev.sh

rerun: ## Relaunch the app quickly during development
	./scripts/rerun-dev.sh

test: ## Run the test suite
	./scripts/test.sh

probe-sources: ## Probe external data sources used by the app
	./scripts/probe-external-sources.sh

lint: ## Run linting and formatting checks when available
	./scripts/lint.sh

archive: ## Create a release archive
	./scripts/archive-release.sh

brand-assets: ## Export app brand assets
	./scripts/export-brand-assets.sh

dmg: ## Build the distributable DMG
	./scripts/create-dmg.sh

release: ## Run the full release flow
	./scripts/release-preflight.sh
	./scripts/sign-and-notarize.sh
	./scripts/publish-update.sh

release-patch: ## Prepare and push a patch release
	./scripts/prepare-release.sh --push patch

release-minor: ## Prepare and push a minor release
	./scripts/prepare-release.sh --push minor

release-major: ## Prepare and push a major release
	./scripts/prepare-release.sh --push major

release-dry-run: ## Dry-run signing and publishing steps
	./scripts/sign-and-notarize.sh --dry-run
	./scripts/publish-update.sh --dry-run

release-setup-notary: ## Store or refresh the notarytool keychain profile (pass APPLE_ID=you@example.com)
	APPLE_ID="$(APPLE_ID)" ./scripts/setup-notary-profile.sh

clean: ## Remove local build artifacts
	rm -rf .build DerivedData
