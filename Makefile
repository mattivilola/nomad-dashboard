APP_NAME := NomadDashboard
SCHEME := NomadDashboard
PROJECT := $(APP_NAME).xcodeproj

.PHONY: bootstrap generate open build run rerun test probe-sources lint archive brand-assets dmg release release-patch release-minor release-major release-dry-run clean

bootstrap:
	./scripts/bootstrap.sh

generate:
	./scripts/generate-project.sh

open:
	./scripts/open-project.sh

build:
	./scripts/build-dev.sh

run:
	./scripts/run-dev.sh

rerun:
	./scripts/rerun-dev.sh

test:
	./scripts/test.sh

probe-sources:
	./scripts/probe-external-sources.sh

lint:
	./scripts/lint.sh

archive:
	./scripts/archive-release.sh

brand-assets:
	./scripts/export-brand-assets.sh

dmg:
	./scripts/create-dmg.sh

release:
	./scripts/sign-and-notarize.sh
	./scripts/publish-update.sh

release-patch:
	./scripts/prepare-release.sh patch

release-minor:
	./scripts/prepare-release.sh minor

release-major:
	./scripts/prepare-release.sh major

release-dry-run:
	./scripts/sign-and-notarize.sh --dry-run
	./scripts/publish-update.sh --dry-run

clean:
	rm -rf .build DerivedData
